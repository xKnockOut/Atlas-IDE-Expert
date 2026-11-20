unit Atlas.IDE.Commands.Adapters.PaletteRegistry;

// Die Befehlspalette der IDE (TAtlasIdePalette) als IAtlasCommandRegistry (#520): Features melden ihre Befehle
// darüber an, ohne die Palette zu kennen. Hält die Palette nicht am Leben; sie gehört der Composition, die auch
// diesen Adapter erzeugt.

interface

uses
  System.SysUtils,
  Atlas.IDE.Commands.Palette,
  Atlas.Core.Commands.Contract;

type
  TAtlasPaletteCommandRegistry = class(TInterfacedObject, IAtlasCommandRegistry)
  private
    FPalette: TAtlasIdePalette;
  public
    constructor Create(APalette: TAtlasIdePalette);
    procedure RegisterCommand(const AId, ACaption, ADescription: string; const AProc: TProc); overload;
    procedure RegisterCommand(const AId, ACaption, ADescription: string; const AProc: TProc;
      const AVisible: TFunc<Boolean>); overload;
  end;

implementation

{ TAtlasPaletteCommandRegistry }

constructor TAtlasPaletteCommandRegistry.Create(APalette: TAtlasIdePalette);
begin
  inherited Create;
  FPalette := APalette;
end;

procedure TAtlasPaletteCommandRegistry.RegisterCommand(const AId, ACaption, ADescription: string;
  const AProc: TProc);
begin
  FPalette.RegisterCommand(AId, ACaption, ADescription, AProc);
end;

procedure TAtlasPaletteCommandRegistry.RegisterCommand(const AId, ACaption, ADescription: string;
  const AProc: TProc; const AVisible: TFunc<Boolean>);
begin
  FPalette.RegisterCommand(AId, ACaption, ADescription, AProc, AVisible);
end;

end.
