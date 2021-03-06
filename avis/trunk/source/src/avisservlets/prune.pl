#!/perl/bin/perl

# Front-end prune script
use PruneLib;

my $module = lc(shift) || usage();;
my $age = shift || usage();
my $profile = shift || "avisservlets.prf";
  
PruneLib::load_profile($profile) || usage();

if ($module eq 'sigs')
  {
    PruneLib::prune_sigs($age);
  }
elsif ($module eq 'logs')
  {
    PruneLib::prune_logs($age);
  }
elsif ($module eq 'samples')
  {
    PruneLib::prune_samples($age);
  }
elsif ($module eq 'all')
  {
    PruneLib::prune_sigs($age);
    PruneLib::prune_logs($age);
    PruneLib::prune_samples($age);
  }
else
  {
    usage();
  }

sub usage
  {
    print "\nusage: \n";
    print "\tperl prune.pl <module> <age> [profile-file]\n";
    print "\n    <module> may be one of the following:\n\n";
    print "\t'sigs'    Prune aged signatures from the database and filesystem\n";
    print "\t'logs'    Prune log files generated by the Gateway Servlets\n";
    print "\t'samples' Prune aged complete samples from the database and filesystem\n";
    print "\t'all'     Prune samples, logs, and signatures older than a certain date\n";
    print "\t          (note: this is equivalent to running prune.pl three times)\n";
    print "\n    <age>\n";
    print "\t          The number of days back from today to start pruning.\n";
    print "\t          (note: an age of '0' is valid. This means that pruning logs\n";
    print "\t          with an age zero WILL delete the live logfile, which is most\n";
    print "\t          likely undesired.)\n\n";
    print "\n    [profile-file]\n";
    print "\t          This is an optional argument specifying the location of the\n";
    print "\t          'avisservlets.prf' file for this gateway.  If left out,\n";
    print "\t          prune.pl will look for avisservlets.prf in the current\n";
    print "\t          working directory.\n";

    exit();
  }
