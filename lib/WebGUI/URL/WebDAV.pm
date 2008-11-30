package WebGUI::URL::WebDAV;

=head1 LEGAL

 -------------------------------------------------------------------
  WebGUI is Copyright 2001-2008 Plain Black Corporation.
 -------------------------------------------------------------------
  Please read the legal notices (docs/legal.txt) and the license
  (docs/license.txt) that came with this distribution before using
  this software.
 -------------------------------------------------------------------
  http://www.plainblack.com                     info@plainblack.com
 -------------------------------------------------------------------

=cut

use strict;
use Apache2::Const -compile => qw(OK DECLINED NOT_FOUND);

use Apache2::WebDAV;
use Filesys::Virtual::Plain;

=head1 NAME

Package WebGUI::URL::MyHandler

=head1 DESCRIPTION

A URL handler that does whatever I tell it to do.

=head1 SYNOPSIS

 use WebGUI::URL::MyHandler;
 my $status = WebGUI::URL::MyHandler::handler($r, $configFile);

=head1 SUBROUTINES

These subroutines are available from this package:

=cut

#-------------------------------------------------------------------

=head2 handler ( request, server, config ) 

The Apache request handler for this package.

=cut

sub handler {
    my ($r, $server, $config) = @_;
    
    my $dav = new Apache2::WebDAV();

    my @handlers = (
        {
            path   => '/Downloads',
            module => 'Filesys::Virtual::Plain',
            args   => {
                root_path => '/Users/doug',
            }
        }
    );
    
    $dav->register_handlers(@handlers);

    $r->push_handlers( PerlResponseHandler => sub {
        $dav->process( $r );
    } );

    return Apache2::Const::DECLINED;
}

1;
#vim:ft=perl

