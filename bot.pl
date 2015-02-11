#!/usr/bin/env perl
use 5.10.3;
use warnings;
use Reddit::Client;
use XML::RSS::Parser;
use XML::Atom::Client;
use HTTP::Tiny;
use HTML::Entities;
use YAML::XS qw/LoadFile DumpFile/;
use Time::Piece;
use Time::Seconds;
use Try::Tiny;
use List::Util 'any';
use URI;

# Globals - these can be put in a config file
our $VERSION      = 0.01;
my $agent_string = "Perly_Bot/v$VERSION";

# posts must mention a Perl keyword to be considered relevant
my $looks_perly = qr/\b(?:perl|cpan|cpanminus|moose|metacpan|modules?)\b/i;

my $datetime_now = localtime;
my $age_threshold= ONE_DAY;
my $ua           = HTTP::Tiny->new( agent => $agent_string );
my $rss          = XML::RSS::Parser->new;
my $feeds_path   = 'feeds.yml';
my $feeds        = LoadFile($feeds_path);
my $cache_path   = 'logs/cached_urls.yml';
my $cache        = LoadFile($cache_path);
my $session_path = 'logs/session_data.json';

open my $ERROR_LOG, '>>', 'logs/error.log' or die $!;

# end globals

unless ($ENV{REDDIT_BOT_USERNAME}
        && $ENV{REDDIT_BOT_PASSWORD})
{
    log_error(
      "Env vars REDDIT_BOT_USERNAME, REDDIT_BOT_PASSWORD are not both defined");
    exit 1;
}

refresh_cache(); # remove stale URLs from cache

# Loop through feeds, check for new posts
for my $feed ( @{$feeds} ) {
    next unless $feed->{active};

    my $date_format = $feed->{pubDateFormat};
    my $date_name   = $feed->{pubDateName};

    my $response = $ua->get( $feed->{url} );
    if ( $response->{success} )
    {
        if ( $feed->{type} eq 'rss' )
        {
            my $posts = $rss->parse_string( $response->{content} );
            foreach my $i ( $posts->query('//item') )
            {
                try {
                    # extract the post date
                    my $datetime =
                      $i->query($date_name)->text_content =~ s/ UTC| GMT//gr;
                    my $datetime_post =
                      Time::Piece->strptime( $datetime, $date_format );

                    if ( $datetime_post > $datetime_now - $age_threshold ) {
                        if (   $i->query('title')->text_content =~ $looks_perly
                            or $i->query('description')->text_content =~
                            $looks_perly )
                        {
                            my $url = $i->query('link')->text_content;

                            if ($feed->{proxy})
                            {
                                $url = get_url_behind_proxy($url);
                                next unless $url;
                            }

                            post_reddit_link(
                                 $i->query('title')->text_content,
                                 $url,
                                 'perl'
                            );
                        }
                    }
                }
                catch {
                    log_error("Error processing $feed->{url}. $_");
                };
            }
        }
        elsif ( $feed->{type} eq 'atom' )
        {
            # accessors are generated from the available tags in the atom feed
            # the tags can have different names, so we store the tag name in feeds.yml
            no strict 'refs';
            my $posts = XML::Atom::Feed->new( Stream => \$response->{content} );
            foreach my $post ( $posts->entries )
            {
                try {
                    # extract the post date
                    my $datetime = $post->$date_name =~ s/ UTC| GMT//gr;
                    my $datetime_post =
                      Time::Piece->strptime( $datetime, $date_format );

                    if ( $datetime_post > $datetime_now - $age_threshold ) {
                        if (   $post->title =~ $looks_perly
                            or $post->summary =~ $looks_perly )
                        {
                            my $url = $post->link->href;

                            if ($feed->{proxy})
                            {
                                $url = get_url_behind_proxy($url);
                                next unless $url;
                            }
                            post_reddit_link(
                                 $post->title,
                                 $url,
                                 'perl'
                            );
                        }
                    }
                }
                catch {
                    log_error("Error processing $feed->{url}. $_");
                };
            }
        }
    }
    else
    {
        log_error(
"Error requesting $feed->{url}. $response->{status} $response->{reason}"
        );
    }
}

sub log_error
{
    my $timestamp = localtime;
    say $ERROR_LOG $timestamp->datetime . "\t$_[0]";
}

sub url_is_cached
{
    my $url = shift;
    any { $url eq $_->{url} } @$cache;
}

sub cache_url
{
    my $url = shift;
    push @$cache, { url => $url, datetime => $datetime_now->datetime };
}

# sieves out stale urls
sub refresh_cache
{
    @$cache = grep {
        my $url_date =
          Time::Piece->strptime( $_->{datetime}, "%Y-%m-%dT%H:%M:%S" );
        $url_date > $datetime_now - $age_threshold ? 1 : 0;
    } @$cache;
}

=head2 post_reddit_link

Posts a link to a subreddit, requires the title, url and subreddit.

=cut

sub post_reddit_link
{
    my ($title, $url, $subreddit) = @_;

    # Return if URL has already been posted
    return if url_is_cached($url);
    cache_url($url);

    my $session_file = $session_path;
    my $reddit       = Reddit::Client->new(
        session_file => $session_file,
        user_agent   => $agent_string,
    );

    unless ( $reddit->is_logged_in ) {
        $reddit->login( $ENV{REDDIT_BOT_USERNAME}, $ENV{REDDIT_BOT_PASSWORD} );
        $reddit->save_session();
    }

    try {
        $reddit->submit_link(
            subreddit => $subreddit,
            title     => decode_entities($title),
            url       => $url
        );
    }
    catch {
        log_error("Error posting $title $url $_");
    };
    sleep(2); # throttle requests to avoid exceeding API limit
}

=head2 get_url_behind_proxy

Requests a proxy URL and returns the ultimate location the URL redirects to. Requires a url as an argument.

=cut

sub get_url_behind_proxy
{
    my $url = shift;
    my $response = HTTP::Tiny->new->get($url);

    if ($response->{success})
    {
        # parse the URL of the article removing the query
        # this reduces the risk of posting a duplicate URL
        # with a different ending
        my $uri = URI->new( $response->{url} );
        return $uri->scheme . '://' . $uri->host . $uri->path;
    }
    else
    {
        log_error("Error requesting proxy $url. $response->{status} $response->{reason}");
    }
    undef;
}

END { DumpFile( $cache_path, $cache ) }
