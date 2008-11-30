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
use Filesys::Virtual::WebGUI;

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
    my ($request, $server, $config) = @_;
    my $session = $request->pnotes('wgSession');
    unless (defined $session) {
        $session = WebGUI::Session->open($server->dir_config('WebguiRoot'), $config->getFilename, $request, $server);
    }
    
    my $dav = new Apache2::WebDAV();
    my @handlers = ( {
        path   => '/files',
        module => 'Filesys::Virtual::WebGUI',
        args   => {
            session => $session,
            root_path => '/files',
        },
    });
    
    $dav->register_handlers(@handlers);

    $request->push_handlers( PerlResponseHandler => sub {
        $dav->process( $request );
    });

    return Apache2::Const::DECLINED;
}

1;
#vim:ft=perl

