# $Id$

use Test::More tests => 7;

BEGIN {
        eval "use Test::Warn";
}

SKIP: {
    use WebService::Validator::HTML::W3C;

    my $v = WebService::Validator::HTML::W3C->new(
                http_timeout    =>  10,
            );

    skip "no internet connection", 7 if -f 't/SKIPLIVE';
    skip "Test:Warn not install", 7 if -f 't/SKIPWARN';
    skip "XML::XPath not installed", 7 if -f 't/SKIPXPATH';


    ok($v, 'object created');
    ok ($v->validate('http://exo.org.uk/code/www-w3c-validator/invalid.html'), 
            'page validated');
            
    my $err;
    warning_is { $err = $v->errors->[0]; } "You should set detailed when initalising if you intend to use the errors method", "set detailed warning";
    isa_ok($err, 'WebService::Validator::HTML::W3C::Error');
    is($err->line, 11, 'Correct line number');
    is($err->col, 6, 'Correct column');
    like($err->msg, qr/end tag for "div" omitted, but OMITTAG NO was specified/,
                    'Correct message');
    
}