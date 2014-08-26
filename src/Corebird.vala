/*  This file is part of corebird, a Gtk+ linux Twitter client.
 *  Copyright (C) 2013 Timm Bäder
 *
 *  corebird is free software: you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation, either version 3 of the License, or
 *  (at your option) any later version.
 *
 *  corebird is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License
 *  along with corebird.  If not, see <http://www.gnu.org/licenses/>.
 */


public class Corebird : Gtk.Application {
  // TODO: Is the static here needed?
  public static Sql.Database db;
  public static GLib.Menu account_menu;
  public signal void account_added (Account acc);
  public signal void account_removed (Account acc);

  const GLib.ActionEntry[] app_entries = {
    {"show-settings",     show_settings_activated         },
    {"quit",              quit_application                },
    {"show-about-dialog", about_activated                 },
    {"show-dm-thread",    show_dm_thread,          "(sx)" },
    {"mark-seen",         mark_seen,               "(sx)" },
    {"show-window",       show_window,             "s"    }
  };


  public Corebird () throws GLib.Error {
    GLib.Object(application_id:   "org.baedert.corebird",
                flags:            ApplicationFlags.HANDLES_COMMAND_LINE);
                //register_session: true);
    this.set_inactivity_timeout (500);
  }

  public override int command_line (ApplicationCommandLine cmd) {
    this.hold ();
    string? compose_screen_name = null;


    OptionEntry[] options = new OptionEntry[2];
    options[0] = {"tweet", 't', 0, OptionArg.STRING, ref compose_screen_name,
            "Shows only the 'compose tweet' window for the given account, nothing else.", "SCREEN_NAME"};
    options[1] = {null};

    string[] args = cmd.get_arguments ();
    string*[] _args = new string[args.length];
    for (int i = 0; i < args.length; i++) {
      _args[i] = args[i];
    }

    try {
      var opt_context = new OptionContext ("");
      opt_context.set_help_enabled (true);
      opt_context.add_main_entries (options, GETTEXT_PACKAGE);
#if VIDEO
      opt_context.add_group (Gst.init_get_option_group ());
#endif
      unowned string[] tmp = _args;
      opt_context.parse (ref tmp);
    } catch (GLib.OptionError e) {
      cmd.print ("Use --help to see available options\n");
      quit ();
      return -1;
    }

    init_log_files ();

    this.add_accelerator (Settings.get_accel ("compose-tweet"), "win.compose-tweet", null);
    this.add_accelerator (Settings.get_accel ("toggle-sidebar"), "win.toggle-sidebar", null);
    this.add_accelerator ("<Alt>1", "win.switch-page", new GLib.Variant.int32(0));
    this.add_accelerator ("<Alt>2", "win.switch-page", new GLib.Variant.int32(1));
    this.add_accelerator ("<Alt>3", "win.switch-page", new GLib.Variant.int32(2));
    this.add_accelerator ("<Alt>4", "win.switch-page", new GLib.Variant.int32(3));
    this.add_accelerator ("<Alt>5", "win.switch-page", new GLib.Variant.int32(4));
    this.add_accelerator ("<Alt>6", "win.switch-page", new GLib.Variant.int32(5));
    this.add_accelerator ("<Alt>7", "win.switch-page", new GLib.Variant.int32(6));
    this.add_accelerator (Settings.get_accel ("show-settings"), "app.show-settings", null);
    this.add_accelerator ("<Control>Q", "app.quit", null);
    this.add_accelerator ("<Control>P", "win.show-account-dialog", null);

    this.add_action_entries (app_entries, this);

    open_startup_windows (compose_screen_name);


    // If the user wants the dark theme, apply it
    var gtk_s = Gtk.Settings.get_default ();
    if (Settings.use_dark_theme ()) {
      gtk_s.gtk_application_prefer_dark_theme = true;
    }

    if (gtk_s.gtk_decoration_layout.contains ("menu")) {
      gtk_s.gtk_decoration_layout = gtk_s.gtk_decoration_layout.replace ("menu", "");
    }

    this.release ();
    return 0;
  }

  private void show_settings_activated () {
    /* We don't set the settings dialog transient to
       any window because we already save its size */
    var dialog = new SettingsDialog (this);
    dialog.show_all ();
  }

  private void about_activated () {
    var active_window = get_active_window ();
    var ad = new AboutDialog ();
    ad.modal = true;
    ad.set_transient_for (active_window);
    ad.show_all ();
  }

  public override void startup () { // {{{
    base.startup ();

    Dirs.create_dirs ();
    debug ("startup");
    Corebird.db = new Sql.Database (Dirs.config ("Corebird.db"),
                                    Sql.COREBIRD_INIT_FILE);

    // Setup gettext
    GLib.Intl.setlocale(GLib.LocaleCategory.ALL, LOCALEDIR);
    GLib.Intl.bindtextdomain (GETTEXT_PACKAGE, null);
    GLib.Intl.bind_textdomain_codeset(GETTEXT_PACKAGE, "UTF-8");
    GLib.Intl.textdomain(GETTEXT_PACKAGE);

    // Construct app menu
    Gtk.Builder builder = new Gtk.Builder ();
    try {
      builder.add_from_resource ("/org/baedert/corebird/ui/menu.ui");
    } catch (GLib.Error e) {
      critical (e.message);
    }
    GLib.MenuModel app_menu = (MenuModel)builder.get_object ("app-menu");
    var acc_menu = app_menu.get_item_link (0, "section");
    account_menu = new GLib.Menu ();

    unowned GLib.SList<Account> accounts = Account.list_accounts ();
    foreach (var acc in accounts) {
      var show_win_action = new SimpleAction ("show-" + acc.screen_name, null);
      show_win_action.activate.connect (()=> {
          add_window_for_screen_name (acc.screen_name);
      });
      add_action(show_win_action);

      var mi = new GLib.MenuItem ("@"+acc.screen_name, "app.show-" + acc.screen_name);
      mi.set_action_and_target_value ("app.show-" + acc.screen_name, null);
      account_menu.append_item (mi);
    }
    ((GLib.Menu)acc_menu).append_submenu (_("Open Account"), account_menu);

    this.set_app_menu (app_menu);

    // Load custom CSS stuff
    Utils.load_custom_css ();
    // Load custom icons
    Utils.load_custom_icons ();


    Twitter.get ().init ();
  } // }}}

  public override void shutdown () {
    base.shutdown();
  }


  /**
   * Open startup windows.
   * Semantics: Open a window for every account in the startup-accounts array.
   * If that array is empty, look at all the account and if there is one, open that one.
   * If there is none, open a MainWindow with a null account.
   */
  private void  open_startup_windows (string? compose_screen_name = null) { // {{{
    if (compose_screen_name != null) {
      Account? acc = Account.query_account (compose_screen_name);
      if (acc == null) {
        critical ("No account named `%s` is configured. Exiting.",
                  compose_screen_name);
        return;
      }
      // TODO: Handle the 'avatar not yet cached' case
      acc.init_proxy ();
      acc.load_avatar ();
      acc.query_user_info_by_scren_name.begin (acc.screen_name, acc.load_avatar);
      var cw = new ComposeTweetWindow (null, acc, null,
                                       ComposeTweetWindow.Mode.NORMAL,
                                       this);
      cw.show();
      this.add_window (cw);
      return;
    }

    string[] startup_accounts = Settings.get ().get_strv ("startup-accounts");
    /* Handle the stupid case where only one item is in the array but it's empty */
    if (startup_accounts.length == 1 && startup_accounts[0] == "")
      startup_accounts.resize (0);

    if (startup_accounts.length == 0) {
      uint n_accounts = Account.list_accounts ().length ();
      if (n_accounts == 1) {
        add_window_for_screen_name (Account.list_accounts ().nth_data (0).screen_name);
      } else if (n_accounts == 0) {
        var window = new MainWindow (this, null);
        add_window (window);
        window.show_all ();
      } else {
        /* We have multiple configured accounts but still none in autostart.
           This should never happen but we handle the case anyway by just opening
           the first one. */
        add_window_for_screen_name (Account.list_accounts ().nth_data (0).screen_name);
      }
    } else {
      foreach (string account in startup_accounts) {
        add_window_for_screen_name (account);
      }
    }
  } // }}}

  /**
   * Initializes log files, i.e. creates the log/ folder and redirects the
   * appropriate handlers for all log levels(i.e. redirects g_message,
   * g_critical, etc. to also print to a file)
   */
  private void init_log_files () { // {{{
    /* First, create that log file */
    //File log_file = File.new_for_path (Dirs.data ("logs/%s.txt".printf (now.to_string())));
    //try {
      //log_stream = log_file.create(FileCreateFlags.REPLACE_DESTINATION);
    //} catch (GLib.Error e) {
      //warning ("Couldn't open log file: %s", e.message);
    //}
    /* If we do not run on the command line, we simply redirect stdout
       to a log file*/
    GLib.Log.set_handler (null, LogLevelFlags.LEVEL_MESSAGE,  print_to_log_file);
    GLib.Log.set_handler (null, LogLevelFlags.LEVEL_ERROR,    print_to_log_file);
    GLib.Log.set_handler (null, LogLevelFlags.LEVEL_CRITICAL, print_to_log_file);
    GLib.Log.set_handler (null, LogLevelFlags.LEVEL_WARNING,  print_to_log_file);
    GLib.Log.set_handler (null, LogLevelFlags.LEVEL_DEBUG,    print_to_log_file);
  } // }}}

  /**
   * Adds a new MainWindow instance with the account that
   * has the given screen name.
   * Note that this only works if the account is already properly
   * set up and won't warn or fail if if isn't.
   *
   * @param screen_name The screen name of the account do add a
   *                    MainWindow for.
   *
   */
  public void add_window_for_screen_name (string screen_name) {
    unowned GLib.SList<Account> accs = Account.list_accounts ();
    foreach (Account a in accs) {
      if (a.screen_name == screen_name) {
        var window = new MainWindow (this, a);
        add_window (window);
        window.show_all ();
        return;
      }
    }
    warning ("Could not add window for account '%s'", screen_name);
  }

  /**
   * Checks if there's currently a MainWindow instance open that has a
   * reference to the account with the given screen name.
   * (This makes a linear search over all open windows, with a text comparison
   * in each iteration)
   *
   * @param screen_name The screen name to search for
   * @return TRUE if a window with the account associated to the given
   *         screen name is open, FALSE otherwise.
   */
  public bool is_window_open_for_screen_name (string screen_name,
                                              out MainWindow? window = null) {
    unowned GLib.List<weak Gtk.Window> windows = this.get_windows ();
    foreach (Gtk.Window win in windows) {
      if (win is MainWindow) {
        if (((MainWindow)win).account.screen_name == screen_name) {
          window = (MainWindow)win;
          return true;
        }
      }
    }
    window = null;
    return false;
  }

  /**
   * Quits the application, saving all open windows and their geometries.
   */
  private void quit_application () {
    unowned GLib.List<weak Gtk.Window> windows = this.get_windows ();
    string[] startup_accounts = Settings.get ().get_strv ("startup-accounts");
    if (startup_accounts.length == 1 && startup_accounts[0] == "")
      startup_accounts.resize (0);


    if (startup_accounts.length != 0) {
      base.quit ();
      return;
    }

    string[] account_names = new string[windows.length ()];
    int index = 0;
    foreach (var win in windows) {
      if (!(win is MainWindow))
        continue;
      var mw = (MainWindow)win;
      string screen_name = mw.account.screen_name;
      mw.save_geometry ();
      account_names[index] = screen_name;
      index ++;
    }
    account_names.resize (index + 1);
    Settings.get ().set_strv ("startup-accounts", account_names);
    base.quit ();
  }


  /**
   * Log handler in case the application is not
   * started from the command line.
   */
  public static void print_to_log_file (string? log_domain, LogLevelFlags flags,
                                        string msg) {
    string out_string;
    if (log_domain == null)
      out_string = msg + "\n";
    else
      out_string = "(%s) %s".printf (log_domain, msg);

#if !DEBUG
    if (flags != LogLevelFlags.LEVEL_DEBUG)
#endif
      stdout.printf (out_string);
  }

  /********************************************************/

  private void show_dm_thread (GLib.SimpleAction a, GLib.Variant? value) {
    // Values: Account screen_name, sender_id
    string account_screen_name = value.get_child_value (0).get_string ();
    int64 sender_id = value.get_child_value (1).get_int64 ();
    MainWindow main_window;
    if (is_window_open_for_screen_name (account_screen_name, out main_window)) {
      main_window.main_widget.switch_page (Page.DM, sender_id);
    } else
      warning ("Window for Account %s is not open, abort.", account_screen_name);
  }

  private void mark_seen (GLib.SimpleAction a, GLib.Variant? value) {
    string screen_name = value.get_child_value (0).get_string ();
    int64 tweet_id = value.get_child_value (1).get_int64 ();
    MainWindow main_window;
    if (is_window_open_for_screen_name (screen_name, out main_window)) {
      message ("Mark as read...");
    } else
      warning ("No window for Account %s found", screen_name);
  }

  private void show_window (GLib.SimpleAction a, GLib.Variant? value) {
    string screen_name = value.get_string ();
    MainWindow main_window;
    if (is_window_open_for_screen_name (screen_name, out main_window))
      main_window.present ();
    else
      warning ("TODO: Implement");
  }
}
