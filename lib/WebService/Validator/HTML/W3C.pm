# $Id: W3C.pm,v 1.1 2003/11/11 22:49:12 struan Exp $
package WebService::Validator::HTML::W3C;

use strict;
use LWP::UserAgent;
use URI::Escape;

use vars qw( $VERSION $VALIDATOR_URI $HTTP_TIMEOUT );

$VERSION = 0.01;
#$VALIDATOR_URI = 'http://validator.w3.org/check';
$VALIDATOR_URI = 'http://validator.exo.org.uk/check';
$HTTP_TIMEOUT = 30;

=head1 NAME

WebService::Validator::HTML::W3C

=head1 SYNOPSIS

    use WebService::Validator::HTML::W3C;

    my $v = WebService::Validator::HTML::W3C->new();

    if ( $v->validate("http://www.example.com/") ) {
        if ( $v->valid ) {
            printf ("%s is a valid website\n", $v->uri);
            } else {
            printf ("%s is not a valid website\n", $v->uri);
            foreach $error ( $v->errors ) {
                printf("%s at line %n\n", $error->{description},
                                          $error->{line_no});
            }
        }
    } else {
        printf ("Failed to validate the website: %s\n", $v->validate_error);
    }

=head1 DESCRIPTION

WebService::Validator::HTML::W3C provides access to the W3C's online
Markup validator. As well as reporting on whether a page is valid it 
also provides access to a detailed list of the errors and where in
the validated document they occur.

=head1 METHODS

=head2 new

    my $v = WebService::Validator::HTML::W3C->new();

Returns a new instance of the WebService::Validator::HTML::W3C object. 

=head2 options

There are various options that can be set when creating the Validator 
object like so:

    my $v = WebService::Validator::HTML::W3C->new( http_timeout => 20 );

=over 4

=item validator_uri

The URI of the validator to use.  By default this accesses the W3Cs validator at http://validator.w3.org/check. If you have a local installation of the validator ( recommended if you wish to do a lot of testing ) or wish to use a validator at another location then you can use this option. Please note that you need to use the full path to the validator cgi.

=item http_timeout

How long (in seconds) to wait for the HTTP connection to timeout when
contacting the validator. By default this is 30 seconds.

=back 

=cut

sub new {
    my $ref = shift;
    my $class = ref $ref || $ref;
    my $obj = {};
    bless $obj, $class;
    $obj->_init(@_);
    return $obj;
}

sub _init {
    my $self = shift;
    my %args = @_;

    $self->http_timeout($args{http_timeout} || $HTTP_TIMEOUT);
    $self->validator_uri($args{validator_uri} || $VALIDATOR_URI);
    $self->_http_method($args{detailed} ? 'GET' : 'HEAD');
    $self->_debug($args{debug}) if $args{debug};
}

=head2 validate

    $v->validate( 'http:://www.example.com/' );

Validate a URI. Returns 0 if the validation fails (e.g if the 
validator cannot be reached), otherwise 1.

=cut

sub validate {
    my $self = shift;
    my $uri = shift;

    unless ( $uri ) {
        $self->validator_error("You need to supply a URI to validate");
        return 0;
    }

    unless ( $uri =~ m(^.*?://) ) {
        $self->validator_error("You need to supply a URI schema (e.g http)");
        return 0;
    }

    my $uri_orig = $uri;
    # creating the HTTP query string with all parameters
    my $req_uri = join('', 
                        "?uri=",
                        uri_escape($uri),
                        ";output=xml"
                    );
    $req_uri= $self->validator_uri . $req_uri;

    my $method = $self->_http_method();
    my $ua = LWP::UserAgent->new( timeout => $self->http_timeout );
    my $request = new HTTP::Request($method, "$req_uri");
    my $response = $ua->simple_request($request);

    if ($response->is_success) # not an error, we could contact the server
    {
        # set both valid and error number according to response
        my $valid = $response->header('X-W3C-Validator-Status');
        my $valid_err_num = $response->header('X-W3C-Validator-Errors');
        
        $self->_content( $response->content() ) 
            if $self->_http_method() !~ /HEAD/;
        
        # we know the validator has been able to (in)validate if 
        # $self->valid is not NULL
        
        if ( ($valid) and ($valid_err_num) ) {
            $self->is_valid(0);
            $self->num_errors($valid_err_num);
            $self->uri($uri_orig);
            return 1;
        } elsif ( !defined $valid ) {
            $self->validator_error('Not a W3C Validator or Bad URI');
            return 0;
        } elsif ( $valid =~ /valid/i ) {
            $self->is_valid(1);
            $self->num_errors($valid_err_num);
            $self->uri($uri_orig);
            return 1;
        }
    } else {
        $self->validator_error('Could not contact validator');
        return 0;
    }
}


=head2 is_valid 

    $v->is_valid;

Returns true (1) if the URI validated otherwise 0.

=cut

sub is_valid {
    my $self = shift;
    my $valid = shift;
    return $self->_accessor('valid', $valid);
}

=head2 uri

    $v->uri();

Returns the URI of the last page on which validation suceeded.

=cut

sub uri {
    my $self = shift;
    my $uri = shift;
    return $self->_accessor('uri', $uri);
}

=head2 num_errors

    $num_errors = $v->num_errors();

Returns the number of errors that the validator encountered.

=cut

sub num_errors {
    my $self = shift;
    my $num_errors = shift;
    return $self->_accessor('num_errors', $num_errors);
}

=head2 errors

    $errors = $v->errors();
    
    foreach my $err ( @$errors ) {
        printf("line: %s, col: %s\n\terror: %s\n", 
                $err->{line}, $err->{col}, $err->{msg});
    }

Returns an array ref of hash refs containing information about each error
encountered.

Note that you need XML::XPath for this to work.

=cut

sub errors {
    my $self = shift;

    return [] unless $self->num_errors();

    my @errs;
    
    eval {
        require XML::XPath;
    };
    if ($@) {
        warn "XML::XPath must be installed in order to get detailed errors";
        return undef;
    } else {
        my $xp = XML::XPath->new( xml => $self->_content() );
        my @messages = $xp->findnodes('/result/messages/msg');

        foreach my $msg ( @messages ) {
            my $err = {};
            $err->{line}  = $msg->getAttribute('line');
            $err->{col}  = $msg->getAttribute('col');
            $err->{msg} = $msg->getChildNode(1)->getValue();

            push @errs, $err;
        }

        return \@errs;
    }
}

=head2 validator_error

    $error = $v->validator_error();

Returns a string indicating why validation may not have occured. This is not
the reason that a webpage was invalid. It is the reason that no meaningful 
information about the attempted validation could be obtained. This is most
likely to be an HTTP error

Possible values are:

=over 4

=item You need to supply a URI to validate

You didn't pass a URI to the validate method

=item You need to supply a URI with a schema

The URI you passed to validate didn't have a schema on the front. The 
W3C validatory can't handle URIs like www.example.com but instead
needs URIs of the form http://www.example.com/.

=item Not a W3C Validator or Bad URI

The URI did not return the headers that WebService::Validator::HTML::W3C 
relies on so it is likely that there is not a W3C Validator at that URI. 
The other possibility is that it didn't like the URI you provided. Sadly
the Validator doesn't give very useful feedback on this at the moment.

=item Could not contact validator

WebService::Validator::HTML::W3C could not establish a connection to the URI.

=back

=cut

sub validator_error {
    my $self = shift;
    my $validator_error = shift;
    return $self->_accessor('validator_error', $validator_error);
}

=head2 validator_uri

    $uri = $v->validator_uri();
    $v->validator_uri('http://validator.w3.org/check');

Returns or sets the URI of the validator to use. Please note that you need
to use the full path to the validator cgi.

=cut

sub validator_uri {
    my $self = shift;
    my $validator_uri = shift;
    return $self->_accessor('validator_uri', $validator_uri);
}

=head2 http_timeout

    $timeout = $v->http_timeout();
    $v->http_timeout(10);

Returns or sets the timeout for the HTTP request.

=cut

sub http_timeout {
    my $self = shift;
    my $http_timeout = shift;
    return $self->_accessor('http_timeout', $http_timeout);
}

sub _http_method {
    my $self = shift;
    my $http_method = shift;
    return $self->_accessor('_http_method', $http_method);
}

sub _content {
    my $self = shift;
    my $content = shift;
    return $self->_accessor('content', $content);
}

sub _debug {
    my $self = shift;
    my $debug_level = shift;
    return $self->_accessor('_debug_level', $debug_level);
}

sub _accessor {
    my $self = shift;
    my ($option, $value) = @_;

    if (defined $value) {
        $self->{$option} = $value;
    }

    return $self->{$option};
}
1;

__END__

=head1 OTHER MODULES

Please note that there is also an official W3C module that is part of the
W3C::LogValidator distribution. However that module is not very useful outside
the constraints of that package. WebService::Validator::HTML::W3C is meant as a more general way to access the W3C Validator.

HTML::Validator uses ngmls to validate against
the W3Cs DTDs. You have to fetch the relevant DTDs and so on.

There is also the HTML::Parser based HTML::Lint which mostly checks for 
known tags rather than XML/HTML validty.

=head1 IMPORTANT

This module is not in any way associated with the W3C so please do not 
report any problems with this module to them. Also please remember that
the online Validator is a shared resource so do not abuse it. This means
sleeping between requests. If you want to do a lot of testing against it
then please consider downloading and installing the Validator software
which is available from the W3C. Debian testing users will also find that 
it is available via apt-get.

=head1 BUGS

While the interface to the Validator seems to be fairly stable it may be 
updated. I will endevour to track any changes with this module so please
check on CPAN for new versions. Also note that this module is only 
gaurunteed to work with the currently stable version of the validator. It
will most likely work with any Beta versions but don't rely on it.

If in doubt please try and run the test suite before reporting bugs. 

That said I'm very happy to hear about bugs. All the more so if they come
with patches ;).

=head1 SUPPORT

author email.

=head1 AUTHOR

	Struan Donald
	struan@cpan.org
	http://www.exo.org.uk/code/

=head1 COPYRIGHT

Copyright (C) 2003 Struan Donald. All rights reserved.

This program is free software; you can redistribute
it and/or modify it under the same terms as Perl itself.

=head1 SEE ALSO

perl(1).

=cut
