Minecraft server management script and systemd unit file
========================================================

Copyright (c) 2013–2014 Scott Zeid.  Released under the X11 License.  
<http://code.s.zeid.me/minecraft-server-manager>

This is a shell script that can be used to start, stop, and control a
Minecraft server (including mods like Bukkit and Sponge), and a systemd
unit file to go along with it.  Neither the unit file nor systemd itself
are required to use the script.

This script uses tmux to background the server.  There is no option to not
use tmux; however, the script should not conflict with other tmux instances.

The script is intended to be contained within its own directory and not
placed on your $PATH.  For a higher-level script that can be placed on
your $PATH (and is also compatible with some other Minecraft server
scripts), see <http://code.s.zeid.me/bin/cb>.

The script is also not designed to be used as a SysV or LSB init script.

Requirements
------------

* tmux
* bash (bash-specific features, like arrays, are used)

Installation
------------

    fedora$ sudo yum install bash tmux git
    ubuntu$ sudo apt-get install bash tmux git
    $ cd /path/to/minecraft-server
    $ git clone https://bitbucket.org/scottywz/minecraft-server-manager.git manager

To update the manager:

    $ cd /path/to/minecraft-server/manager
    $ git pull

Configuration
-------------

The script needs to be configured before you can use it.  Default settings
are contained in `manager.conf.defaults`, and custom settings should
be stored in a file called just `manager.conf`.  Pretty much all the
variables defined in the defaults file should be self-explanatory, except
for the "Advanced tmux options" section.  However, the defaults file does
contain some informational comments, which should be considered a
supplement to this README and are worth reading.

The one default particularly worth noting is `$BASE_PATH`, which defaults
to the parent directory of the directory in which the script is contained.

To override a variable, create or edit `manager.conf` and set the
variable as you would in a bash script.  The conf file is sourced as a
bash script, so any bash-specific features may be used.

You may (and should) reference other variables within a value in order to
avoid repetition.  For example:

    JAR_PATH=$BASE_PATH/minecraft-server.jar

as opposed to:

    JAR_PATH=/whatever/lengthy/value/to/which/BASE_PATH/is/set/minecraft-server.jar

This is possible because the defaults file is sourced *after* the user
settings file, and the defaults file only sets variables if they are
already set.  (See the comments in the defaults file for details.)

To use a different name/path for the user config file, use the -c/--config
argument (must be the first argument).

If you are also using the systemd unit file, you will also need to modify the
paths contained therein and then configure systemd to use it.

License
-------

This code is [free software](https://gnu.org/philosophy/free-sw.html) licensed
under the terms of the [X11 License](https://tldrlegal.com/license/x11-license):

```
Copyright (c) Scott Zeid.  <http://s.zeid.me/>

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.

Except as contained in this notice, the name(s) of the above copyright holders
shall not be used in advertising or otherwise to promote the sale, use or
other dealings in this Software without prior written authorization.
```
