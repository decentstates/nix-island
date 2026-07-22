{ lib, ... }:

{
  options = {
    execWrappers = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = ''
        Scripts that exec each other, left-to-right.
        
        Use lib.mkOrder if you need ordering.
        # TODO: There is probably a better system to specify before or after
        # other named exec wrappers. Some sort of graph tool.
      '';
    };
  };
}
