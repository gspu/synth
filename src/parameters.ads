--  This file is covered by the Internet Software Consortium (ISC) License
--  Reference: ../License.txt

with Ada.Strings.Unbounded;
with Config;

with Definitions;  use Definitions;

package Parameters is

   package SU  renames Ada.Strings.Unbounded;

   live_system : constant String := "Live System";
   type configuration_record is
      record
         dir_repository  : SU.Unbounded_String;
         dir_packages    : SU.Unbounded_String;
         dir_portsdir    : SU.Unbounded_String;
         dir_distfiles   : SU.Unbounded_String;
         dir_buildbase   : SU.Unbounded_String;
         dir_localbase   : SU.Unbounded_String;
         dir_logs        : SU.Unbounded_String;
         dir_ccache      : SU.Unbounded_String;
         num_builders    : builders;
         jobs_limit      : builders;
         tmpfs_workdir   : Boolean;
         tmpfs_localbase : Boolean;
      end record;

   configuration : configuration_record;

   --  This procedure will create a default configuration file if one
   --  does not already exist, otherwise it will it load it.  In every case,
   --  the "configuration" record will be populated after this is run.
   --  returns "True" on success
   function load_configuration (num_cores : cpu_range;
                                profile   : String := live_system)
                                return Boolean;

private

   internal_config : Config.Configuration;
   distfiles_loc   : SU.Unbounded_String;

   make_query      : exception;

   --  Default Sizing by number of CPUS
   --      1 CPU ::  1 Builder,  1 job  per builder
   --    2/3 CPU ::  2 builders, 2 jobs per builder
   --    4/5 CPU ::  3 builders, 3 jobs per builder
   --    6/7 CPU ::  4 builders, 3 jobs per builder
   --    8/9 CPU ::  6 builders, 4 jobs per builder
   --  10/11 CPU ::  8 builders, 4 jobs per builder
   --    12+ CPU :: floor (75% * CPU), 5 jobs per builder

   --  Each section is identical, but represents a profile
   --  Selection 1 is the live system, a.k.a "[Live System]"
   --  LS_Distfiles  : String := "/usr/ports/distfiles";  (Queried)
   --  LS_Builders   : Integer  (Queried, see cpu-based presets)
   --  LS_Jobs_limit : Integer  (Queried, see cpu-based presets)

   LS_Packages    : constant String := "/var/synth/live_packages";
   LS_Logs        : constant String := "/var/log/synth";
   LS_Buildbase   : constant String := "/usr/obj/synth-live";
   conf_location  : constant String := "/usr/local/etc/synth.ini";
   std_ports_loc  : constant String := "/usr/ports";
   std_distfiles  : constant String := "/usr/ports/distfiles";
   no_ccache      : constant String := "disabled";

   Field_01 : constant String := "Directory_packages";
   Field_02 : constant String := "Directory_repository";
   Field_03 : constant String := "Directory_portsdir";
   Field_04 : constant String := "Directory_distfiles";
   Field_05 : constant String := "Directory_buildbase";
   Field_06 : constant String := "Directory_logs";
   Field_07 : constant String := "Directory_ccache";
   Field_08 : constant String := "Number_of_builders";
   Field_09 : constant String := "Max_jobs_per_builder";
   Field_10 : constant String := "TmpFS_workdir";
   Field_11 : constant String := "TmpFS_localbase";

   procedure default_parallelism (num_cores : cpu_range;
                                  num_builders : out Integer;
                                  jobs_per_builder : out Integer);

   --  These pull requested configuration information.  If they aren't set,
   --  they'll set it to the default (which it also returns);
   function extract_string  (profile, mark, default : String)
                             return SU.Unbounded_String;
   function extract_boolean (profile, mark : String; default : Boolean)
                             return Boolean;
   function extract_integer (profile, mark : String; default : Integer)
                             return Integer;

   function section_exists (profile : String) return Boolean;
   function all_params_present (profile : String) return Boolean;
   function generated_section return String;
   function param_set (profile, field : String) return Boolean;
   function query_distfiles return String;

end Parameters;