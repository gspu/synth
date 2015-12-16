--  This file is covered by the Internet Software Consortium (ISC) License
--  Reference: ../License.txt

with Ada.Directories;
with Ada.Text_IO;
with Ada.Characters.Latin_1;
with Util.Streams.Pipes;
with Util.Streams.Buffered;

package body Parameters is

   package AD  renames Ada.Directories;
   package TIO renames Ada.Text_IO;
   package STR renames Util.Streams;
   package LAT renames Ada.Characters.Latin_1;

   --------------------------
   --  load_configuration  --
   --------------------------
   function load_configuration (num_cores : cpu_range;
                                profile   : String := live_system)
                                return Boolean
   is
      def_builders   : Integer;
      def_jlimit     : Integer;
      fields_present : Boolean;
   begin
      default_parallelism (num_cores        => num_cores,
                           num_builders     => def_builders,
                           jobs_per_builder => def_jlimit);

      if not AD.Exists (conf_location) then
         declare
            File_Handle : TIO.File_Type;
         begin
            TIO.Create (File => File_Handle,
                        Mode => TIO.Out_File,
                        Name => conf_location);
            TIO.Put_Line (File_Handle, "; This Synth configuration file is " &
                            "automatically generated");
            TIO.Put_Line (File_Handle, "; Take care when hand editing!");
            TIO.Close (File => File_Handle);
         exception
            when Error : others =>
               TIO.Put_Line ("Failed to create " & conf_location);
               return False;
         end;
      end if;

      internal_config.Init (File_Name => conf_location,
                            On_Type_Mismatch => Config.Be_Quiet);

      if section_exists (profile => profile) then
         fields_present := all_params_present (profile);
      else
         declare
            File_Handle : TIO.File_Type;
         begin
            TIO.Open (File => File_Handle,
                      Mode => TIO.Append_File,
                      Name => conf_location);
            TIO.Put_Line (File_Handle, "");
            TIO.Put_Line (File_Handle, "[" & profile & "]");
            TIO.Close (File_Handle);
         exception
            when Error : others =>
               TIO.Put_Line ("Failed to append " & conf_location);
               return False;
         end;
         fields_present := False;
      end if;

      configuration.dir_packages :=
        extract_string (profile, Field_01, LS_Packages);

      configuration.dir_repository := configuration.dir_packages;
      SU.Append (configuration.dir_repository, "/All");

      configuration.dir_portsdir :=
        extract_string (profile, Field_03, std_ports_loc);

      if param_set (profile, Field_04) then
         configuration.dir_distfiles :=
           extract_string (profile, Field_04, std_distfiles);
      else
         configuration.dir_distfiles :=
           extract_string (profile, Field_04, query_distfiles);
      end if;

      configuration.dir_buildbase :=
        extract_string (profile, Field_05, LS_Buildbase);

      configuration.dir_logs :=
        extract_string (profile, Field_06, LS_Logs);

      configuration.dir_ccache :=
        extract_string (profile, Field_07, no_ccache);

      configuration.num_builders := builders
        (extract_integer (profile, Field_08, def_builders));

      configuration.jobs_limit := builders
        (extract_integer (profile, Field_09, def_jlimit));

      configuration.tmpfs_workdir :=
        extract_boolean (profile, Field_10, True);

      configuration.tmpfs_localbase :=
        extract_boolean (profile, Field_11, True);

      if not fields_present then
         declare
            contents : String := generated_section;
         begin
            internal_config.Replace_Section (profile, contents);
         exception
            when Error : others =>
               TIO.Put_Line ("Failed to update [" & profile & "] at "
                 & conf_location);
               return False;
         end;
      end if;

      return True;
   end load_configuration;


   ---------------------------
   --  default_parallelism  --
   ---------------------------
   procedure default_parallelism (num_cores : cpu_range;
                                  num_builders : out Integer;
                                  jobs_per_builder : out Integer)
   is
   begin
      case num_cores is
         when 1 =>
            num_builders := 1;
            jobs_per_builder := 1;
         when 2 | 3 =>
            num_builders := 2;
            jobs_per_builder := 2;
         when 4 | 5 =>
            num_builders := 3;
            jobs_per_builder := 3;
         when 6 | 7 =>
            num_builders := 4;
            jobs_per_builder := 3;
         when 8 | 9 =>
            num_builders := 6;
            jobs_per_builder := 4;
         when 10 | 11 =>
            num_builders := 8;
            jobs_per_builder := 4;
         when others =>
            num_builders := (Integer (num_cores) * 3) / 4;
            jobs_per_builder := 5;
      end case;
   end default_parallelism;


   ----------------------
   --  extract_string  --
   ----------------------
   function extract_string  (profile, mark, default : String)
                             return SU.Unbounded_String
   is
   begin
      return SU.To_Unbounded_String
        (internal_config.Value_Of (profile, mark, default));
   end extract_string;


   -----------------------
   --  extract_boolean  --
   -----------------------
   function extract_boolean (profile, mark : String; default : Boolean)
                             return Boolean
   is
   begin
      return internal_config.Value_Of (profile, mark, default);
   end extract_boolean;


   -----------------------
   --  extract_integer  --
   -----------------------
   function extract_integer (profile, mark : String; default : Integer)
                             return Integer is
   begin
      return internal_config.Value_Of (profile, mark, default);
   end extract_integer;


   -----------------
   --  param_set  --
   -----------------
   function param_set (profile, field : String) return Boolean
   is
      garbage : constant String := "this-is-garbage";
   begin
      return internal_config.Value_Of (profile, field, garbage) /= garbage;
   end param_set;


   ----------------------
   --  section_exists  --
   ----------------------
   function section_exists (profile : String) return Boolean is
   begin
      return param_set (profile, Field_01);
   end section_exists;

   --------------------------
   --  all_params_present  --
   --------------------------
   function all_params_present (profile : String) return Boolean is
   begin
      return
        param_set (profile, Field_01) and then
        param_set (profile, Field_02) and then
        param_set (profile, Field_03) and then
        param_set (profile, Field_04) and then
        param_set (profile, Field_05) and then
        param_set (profile, Field_06) and then
        param_set (profile, Field_07) and then
        param_set (profile, Field_08) and then
        param_set (profile, Field_09) and then
        param_set (profile, Field_10) and then
        param_set (profile, Field_11);
   end all_params_present;


   -------------------------
   --  generated_section  --
   -------------------------
   function generated_section return String
   is
      function USS (US : SU.Unbounded_String) return String;
      function BDS (BD : builders) return String;
      function TFS (TF : Boolean) return String;

      function USS (US : SU.Unbounded_String) return String is
      begin
         return "= " & SU.To_String (US) & LAT.LF;
      end USS;
      function BDS (BD : builders) return String
      is
         BDI : constant String := Integer'Image (Integer (BD));
      begin
         return LAT.Equals_Sign & BDI & LAT.LF;
      end BDS;
      function TFS (TF : Boolean) return String is
      begin
         if TF then
            return LAT.Equals_Sign & " true" & LAT.LF;
         else
            return LAT.Equals_Sign & " false" & LAT.LF;
         end if;
      end TFS;
   begin
      return
        Field_01 & USS (configuration.dir_packages) &
        Field_02 & USS (configuration.dir_repository) &
        Field_03 & USS (configuration.dir_portsdir) &
        Field_04 & USS (configuration.dir_distfiles) &
        Field_05 & USS (configuration.dir_buildbase) &
        Field_06 & USS (configuration.dir_logs) &
        Field_07 & USS (configuration.dir_ccache) &
        Field_08 & BDS (configuration.num_builders) &
        Field_09 & BDS (configuration.jobs_limit) &
        Field_10 & TFS (configuration.tmpfs_workdir) &
        Field_11 & TFS (configuration.tmpfs_localbase);
   end generated_section;


   -----------------------
   --  query_distfiles  --
   -----------------------
   function query_distfiles return String
   is
      command  : constant String := "make -C " &
        SU.To_String (configuration.dir_portsdir) &
        "/ports-mgmt/pkg -V DISTDIR";
      pipe     : aliased STR.Pipes.Pipe_Stream;
      buffer   : STR.Buffered.Buffered_Stream;
      content  : SU.Unbounded_String;
      status   : Integer;
      CR_loc   : Integer;
      CR       : constant String (1 .. 1) := (1 => Character'Val (10));
   begin
      pipe.Open (Command => command);
      buffer.Initialize (Output => null,
                         Input  => pipe'Unchecked_Access,
                         Size   => 4096);
      buffer.Read (Into => content);
      pipe.Close;
      status := pipe.Get_Exit_Status;
      if status /= 0 then
         raise make_query with command;
      end if;
      CR_loc := SU.Index (Source => content, Pattern => CR);

      return SU.Slice (Source => content, Low => 1, High => CR_loc - 1);
   end query_distfiles;


end Parameters;