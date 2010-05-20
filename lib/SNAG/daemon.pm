package SNAG::daemon;

use Moose::Role;
use File::Spec::Functions qw/rootdir catpath catfile devnull catdir/;
use POSIX;

sub daemonize
{
	my $self = shift;
  if($self->OS eq 'Windows')
  {
    ## Can't do service stuff here because Win32::Daemon can't be required in at runtime, something is missed and it never responds to the SCM
  }
  else
  {
    umask(0);

    chdir '/' or die $!;

    open(STDIN, "+>" . File::Spec->devnull());
    open(STDOUT, "+>&STDIN");
    open(STDERR, "+>&STDIN");
  
    foreach my $sig ($SIG{TSTP}, $SIG{TTIN}, $SIG{TTOU}, $SIG{HUP}, $SIG{PIPE})
    {
      $sig = 'IGNORE';
    }
  
    my $pid = &safe_fork;
    exit if $pid;
    die("Daemonization failed!") unless defined $pid;
  
    POSIX::setsid() or die "SERVER: Can't start a new session: $!";
  }
}

sub safe_fork
{
  my $pid;
  my $retry = 0;

  FORK:
  {
    if(defined($pid=fork))
    {
      return $pid;
    }
    elsif($!=~/No more process/i)
    {
      if(++$retry>(3))
      {
        die "Cannot fork process, retry count exceeded: $!";
      }

      sleep (5);
      redo FORK;
    }
    else
    {
      die "Cannot fork process: $!";
    }
  }
}

sub already_running
{
	my $self = shift;
  if($self->OS eq 'Windows')
  {
  # print "RUNNING already_running!\n";
  # require Win32::Process::Info;

  # my $script_name = SCRIPT_NAME;

  # return grep { $_->{CommandLine} =~ /perl.+$script_name/ && $_->{ProcessId} != $$ } @{Win32::Process::Info->new()->GetProcInfo()};
  }
  else
  {
    require Proc::ProcessTable;

    my $full_script = "($^X|perl) $0";

    #return grep { $_->fname eq SCRIPT_NAME && $_->pid != $$ } @{(new Proc::ProcessTable)->table};
    return grep { $_->cmndline =~ /^$full_script/ && $_->pid != $$ } @{(new Proc::ProcessTable)->table};
  }
}

1;
