# Add to a home-manager configuration:
#   imports = [ nix-holm.homeManagerModules.holm ];
# directory defaults to ~/holms/<name>; username/stateVersion to the
# outer home's.
{ pkgs, ... }:
{
  holm.shells = {
    work-shell = {
      tcpPorts = [ 443 22 ];
      modules = [
        ({ pkgs, ... }: {
          home.packages = with pkgs; [ ripgrep jq gh kubectl ];
          programs.bash.enable = true;
          programs.starship.enable = true;
          programs.git = {
            enable = true;
            userName = "Alice @ Work";
            userEmail = "alice@corp.example";
          };
          programs.ssh = {
            enable = true;
            # ~ = the HOLM's home
            matchBlocks."git.corp.example".identityFile = "~/.ssh/id_work";
          };
          home.sessionVariables.KUBECONFIG = "$HOME/.kube/work.yaml";
        })
      ];
    };

    oss-shell = {
      tcpPorts = [ 443 22 ];
      shell = pkgs.zsh; # pair with programs.zsh.enable
      modules = [
        ({ pkgs, ... }: {
          home.packages = with pkgs; [ ripgrep tokei ];
          programs.zsh.enable = true;
          programs.git = {
            enable = true;
            userName = "alicehacks";
            userEmail = "alice@personal.example";
          };
        })
      ];
    };

    # no tcpPorts = offline
    untrusted-run.modules = [
      ({ pkgs, ... }: { home.packages = [ pkgs.nodejs ]; })
    ];
  };
}
