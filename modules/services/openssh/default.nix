# This stub module is not designed to replace the macOS sshd, but rather only to
# add configurable authorized keys and keyfiles to users. In order to change
# settings reversibly in sshd_config, this module uses the following
# replacement:
#   OriginalOption
# is replaced with:
#   OverridingOption # Overridden by nix-darwin: OriginalOption
# When this module is disabled, all overridden options will be restored.

{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.openssh;

  userOptions = {
    openssh.authorizedKeys = {
      keys = mkOption {
        type = types.listOf types.str;
        default = [];
        description = ''
          A list of verbatim OpenSSH public keys that should be added to the
          user's authorized keys. The keys are added to a file that the SSH
          daemon reads in addition to the the user's authorized_keys file.
          You can combine the <literal>keys</literal> and
          <literal>keyFiles</literal> options.
          Warning: If you are using <literal>NixOps</literal> then don't use this
          option since it will replace the key required for deployment via ssh.
        '';
      };

      keyFiles = mkOption {
        type = types.listOf types.path;
        default = [];
        description = ''
          A list of files each containing one OpenSSH public key that should be
          added to the user's authorized keys. The contents of the files are
          read at build time and added to a file that the SSH daemon reads in
          addition to the the user's authorized_keys file. You can combine the
          <literal>keyFiles</literal> and <literal>keys</literal> options.
        '';
      };
    };
  };

  authKeysFiles = let
    mkAuthKeyFile = u: nameValuePair "ssh/authorized_keys.d/${u.name}" {
      source = pkgs.writeText "${u.name}-authorized_keys" ''
        ${concatStringsSep "\n" u.openssh.authorizedKeys.keys}
        ${concatMapStrings (f: readFile f + "\n") u.openssh.authorizedKeys.keyFiles}
      '';
    };

    usersWithKeys = attrValues (flip filterAttrs config.users.users (n: u:
      length u.openssh.authorizedKeys.keys != 0 || length u.openssh.authorizedKeys.keyFiles != 0
    ));

  in listToAttrs (map mkAuthKeyFile usersWithKeys);

  sshBool = b: if b then "yes" else "no";
  overrideSSHConfig = key: value: ''
    sed -i 's|^\(${key}.*\)$|${key} ${value} # Overridden by nix-darwin: \1|g' /etc/ssh/sshd_config
  '';

  restoreSSHConfig = ''
    sed -i 's|^\(.*\)# Overridden by nix-darwin: (.*)$|\2|g' /etc/ssh/sshd_config
  '';

in {
  options = {
    services.openssh = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Whether to enable the OpenSSH secure shell daemon, which
          allows secure remote logins.
        '';
      };

      passwordAuthentication = mkOption {
        type = types.bool;
        default = true;
        description = ''
          Specifies whether password authentication is allowed.
        '';
      };

      challengeResponseAuthentication = mkOption {
        type = types.bool;
        default = true;
        description = ''
          Specifies whether challenge/response authentication is allowed.
        '';
      };
    };

    users.users = mkOption {
      options = [ userOptions ];
    };
  };

  config = {
    environment.etc = authKeysFiles;

    system.activationScripts.postActivation.text = ''
      ${restoreSSHConfig}
      ${if cfg.enable then ''
        echo Applying changes to /etc/ssh/sshd_config
        ${
          concatStrings (mapAttrsToList overrideSSHConfig {
            AuthorizedKeysFile = ".ssh/authorized_keys /etc/ssh/authorized_keys.d/%u";
            PasswordAuthentication = sshBool cfg.passwordAuthentication;
            ChallengeResponseAuthentication = sshBool cfg.challengeResponseAuthentication;
          })
        }
      '' else ""}
    '';
  };
}
