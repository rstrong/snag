package SNAG::logger;

use Moose::Role;
use POE;
use Mail::Sendmail;


# Should make this just an attribute?
our %flags;

sub logger
{
	my $self = shift;
  ###########################
  ## SET UP LOGGER
  ###########################
  POE::Session->create
  (
    inline_states =>
    {
      _start => sub
      {
	my ($kernel, $heap) = @_[KERNEL, HEAP];

	$kernel->alias_set('logger');

	$SIG{__WARN__} = sub
	{
	  $kernel->call('logger' => 'log' => "SNAG warning: @_");
	};
      },

      log => sub
      {
        my ($kernel, $heap, $msg) = @_[ KERNEL, HEAP, ARG0 ];

        my ($fh, $logfile, $logdate, $time);

        $time = time();

        $logdate = time2str("%w", $time);

        if ($heap->{logdate} ne $logdate)
        {
          if (defined $heap->{'log'})
          {
            $heap->{'log'}->close();
            delete $heap->{'log'};
          }
        }

        unless($fh = $heap->{'log'})
        {
          ### Needs to be a 2 liner because as a windows service, SCRIPT_NAME only returns 'SNAG'
          (my $logname = $self->SCRIPT_NAME) =~ s/\.\w+$//;
          $logname .= '.log';

          $logfile = catfile($self->LOG_DIR, "$logname.$logdate");

          if ($heap->{logdate} ne $logdate)
          {
            # Check if logfile was modified in the last day, so we can append rather than overwrite
            if(time() - (stat($logfile))[9] < 3600)
            {
              $fh = new FileHandle ">> $logfile" or die "Could not open log $logfile";
            }
            else
            {
              $fh = new FileHandle "> $logfile" or die "Could not open log $logfile"
            }
          }
          else
          {
            $fh = new FileHandle ">> $logfile" or die "Could not open log $logfile";
          }

          $fh->autoflush(1);

          $heap->{logdate} = $logdate;

          $heap->{'log'} = $fh;
        }

        chomp $msg;
        my $now = time2str("%Y-%m-%d %T", $time);
        print $fh "[$now] $msg\n";
        print "[$now] $msg\n" if $flags{debug};
      },

      alert => sub
      {
        my ($kernel, $heap, $args) = @_[ KERNEL, HEAP, ARG0 ];

        my %defaults = 
        (
         smtp    => $self->SMTP,
         To      => $self->SENDTO,
         From    => $self->SENDTO,
         Subject => "SNAG alert from " . $self->HOST_NAME . "!",
         Message => "Default message",
        );

        my %mail = (%defaults, %$args);

        if($self->OS eq 'Windows')
	      {
	        eval
	        {
	          sendmail(%mail) or die $Mail::Sendmail::error; 
	        };
	        if($@)
	        {
            $kernel->yield('log' => "Could not send alert because of an error.  Error: $@, Subject: $mail{Subject}, Message: $mail{Message}");
	        }
	      }
	      else
	      {
          require POE::Wheel::Run;

          unless($heap->{alert_wheel})
          {
            $heap->{mail_args} = \%mail;

	          $heap->{alert_wheel} = POE::Wheel::Run->new
            (
              Program => sub
              {
                sendmail(%mail) or die $Mail::Sendmail::error; 
              },
              StdioFilter  => POE::Filter::Line->new(),
              StderrFilter => POE::Filter::Line->new(),
              Conduit      => 'pipe',
              StdoutEvent  => 'alert_stdio',
              StderrEvent  => 'alert_stderr',
              CloseEvent   => "alert_close",
            );
          }
          else
          { 
            $kernel->yield('log' => "Could not send alert because an alert wheel is already running.  Subject: $mail{Subject}, Message: $mail{Message}");
          }
        }
      },
    
      alert_stdio => sub
      {
      },
    
      alert_stderr => sub
      {
	      my ($kernel, $heap, $error) = @_[ KERNEL, HEAP, ARG0 ];
        $kernel->yield('log' => "Could not send alert because of an error.  Error: $error, Subject: $heap->{mail_args}->{Subject}, Message: $heap->{mail_args}->{Message}");
      },

      alert_close => sub
      {
	      my ($kernel, $heap) = @_[ KERNEL, HEAP ];
        delete $heap->{alert_wheel};
      },
    }
  );
}

1;
