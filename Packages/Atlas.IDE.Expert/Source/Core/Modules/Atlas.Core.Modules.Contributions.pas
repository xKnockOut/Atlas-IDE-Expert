unit Atlas.Core.Modules.Contributions;

// Beiträge der Module einsammeln (#1455, Regel 2 und 4): Base fragt die
// Registry bei Bedarf nach allen bereitgestellten Quellen, statt sie einmal
// beim Start zu lesen. So erscheinen und verschwinden Befehle, Menüeinträge
// und Hörer mit ihrem Modul. Ein Fehler in einem Beitrag hält die übrigen nicht
// an; ApplySettings und ThemeChanged liefern die Fehler als
// „Interface: Klasse: Meldung“.

interface

uses
  System.SysUtils,
  Atlas.Core.Modules.Contract;

type
  TAtlasModuleContributions = class
  public
    /// <summary>Alle Befehle in Reihenfolge der Bereitstellung; ohne Registry leer.</summary>
    class function Commands(const ARegistry: IAtlasModuleRegistry): TArray<TAtlasModuleCommand>; static;
    /// <summary>Befehl AId; False, wenn ihn kein Modul anbietet.</summary>
    class function FindCommand(const ARegistry: IAtlasModuleRegistry; const AId: string;
      out ACommand: TAtlasModuleCommand): Boolean; static;
    /// <summary>Sichtbar ist ein Befehl ohne Visible oder wenn Visible True liefert.</summary>
    class function IsVisible(const ACommand: TAtlasModuleCommand): Boolean; static;
    /// <summary>Menüeinträge für APlace in Reihenfolge der Bereitstellung.</summary>
    class function MenuEntries(const ARegistry: IAtlasModuleRegistry;
      APlace: TAtlasMenuPlace): TArray<TAtlasMenuEntry>; static;
    /// <summary>Tastenkürzel aller Module; Einträge ohne Taste (0) oder ohne Attempt fehlen.</summary>
    class function Keys(const ARegistry: IAtlasModuleRegistry): TArray<TAtlasModuleKey>; static;
    class function EditorViewActivated(const ARegistry: IAtlasModuleRegistry): TArray<string>; static;
    class function ApplySettings(const ARegistry: IAtlasModuleRegistry): TArray<string>; static;
    class function ThemeChanged(const ARegistry: IAtlasModuleRegistry): TArray<string>; static;
    /// <summary>Erster nicht leerer Beitrag; '' ohne.</summary>
    class function HoverValue(const ARegistry: IAtlasModuleRegistry; const AExpression: string;
      const ATypeChain: TArray<string>; const AText: string): string; static;
  end;

implementation

class function TAtlasModuleContributions.Commands(const ARegistry: IAtlasModuleRegistry): TArray<TAtlasModuleCommand>;
var
  mItem: IInterface;
  mSource: IAtlasCommandSource;
begin
  Result := nil;
  if ARegistry = nil then
    Exit;
  for mItem in ARegistry.FindAll(IAtlasCommandSource) do
    if Supports(mItem, IAtlasCommandSource, mSource) then
      Result := Result + mSource.Commands;
end;

class function TAtlasModuleContributions.FindCommand(const ARegistry: IAtlasModuleRegistry; const AId: string;
  out ACommand: TAtlasModuleCommand): Boolean;
var
  mCommand: TAtlasModuleCommand;
begin
  Result := False;
  ACommand := Default(TAtlasModuleCommand);
  for mCommand in Commands(ARegistry) do
    if SameText(mCommand.Id, AId) then
    begin
      ACommand := mCommand;
      Exit(True);
    end;
end;

class function TAtlasModuleContributions.IsVisible(const ACommand: TAtlasModuleCommand): Boolean;
begin
  Result := not Assigned(ACommand.Visible) or ACommand.Visible();
end;

class function TAtlasModuleContributions.MenuEntries(const ARegistry: IAtlasModuleRegistry;
  APlace: TAtlasMenuPlace): TArray<TAtlasMenuEntry>;
var
  mItem: IInterface;
  mSource: IAtlasMenuSource;
  mEntry: TAtlasMenuEntry;
begin
  Result := nil;
  if ARegistry = nil then
    Exit;
  for mItem in ARegistry.FindAll(IAtlasMenuSource) do
    if Supports(mItem, IAtlasMenuSource, mSource) then
      for mEntry in mSource.MenuEntries do
        if mEntry.Place = APlace then
          Result := Result + [mEntry];
end;

class function TAtlasModuleContributions.Keys(const ARegistry: IAtlasModuleRegistry): TArray<TAtlasModuleKey>;
var
  mItem: IInterface;
  mSource: IAtlasKeySource;
  mKey: TAtlasModuleKey;
begin
  Result := nil;
  if ARegistry = nil then
    Exit;
  for mItem in ARegistry.FindAll(IAtlasKeySource) do
    if Supports(mItem, IAtlasKeySource, mSource) then
      for mKey in mSource.Keys do
        if (mKey.Key <> 0) and Assigned(mKey.Attempt) then
          Result := Result + [mKey];
end;

class function TAtlasModuleContributions.EditorViewActivated(const ARegistry: IAtlasModuleRegistry): TArray<string>;
var
  mItem: IInterface;
  mListener: IAtlasFollowsEditorView;
begin
  Result := nil;
  if ARegistry = nil then
    Exit;
  for mItem in ARegistry.FindAll(IAtlasFollowsEditorView) do
    if Supports(mItem, IAtlasFollowsEditorView, mListener) then
      try
        mListener.EditorViewActivated;
      except
        on mError: Exception do
          Result := Result + ['IAtlasFollowsEditorView: ' + mError.ClassName + ': ' + mError.Message];
      end;
end;

class function TAtlasModuleContributions.ApplySettings(const ARegistry: IAtlasModuleRegistry): TArray<string>;
var
  mItem: IInterface;
  mListener: IAtlasAppliesSettings;
begin
  Result := nil;
  if ARegistry = nil then
    Exit;
  for mItem in ARegistry.FindAll(IAtlasAppliesSettings) do
    if Supports(mItem, IAtlasAppliesSettings, mListener) then
      try
        mListener.ApplySettings;
      except
        on mError: Exception do
          Result := Result + ['IAtlasAppliesSettings: ' + mError.ClassName + ': ' + mError.Message];
      end;
end;

class function TAtlasModuleContributions.ThemeChanged(const ARegistry: IAtlasModuleRegistry): TArray<string>;
var
  mItem: IInterface;
  mListener: IAtlasFollowsTheme;
begin
  Result := nil;
  if ARegistry = nil then
    Exit;
  for mItem in ARegistry.FindAll(IAtlasFollowsTheme) do
    if Supports(mItem, IAtlasFollowsTheme, mListener) then
      try
        mListener.ThemeChanged;
      except
        on mError: Exception do
          Result := Result + ['IAtlasFollowsTheme: ' + mError.ClassName + ': ' + mError.Message];
      end;
end;

class function TAtlasModuleContributions.HoverValue(const ARegistry: IAtlasModuleRegistry; const AExpression: string;
  const ATypeChain: TArray<string>; const AText: string): string;
var
  mItem: IInterface;
  mSource: IAtlasHoverValueSource;
begin
  Result := '';
  if ARegistry = nil then
    Exit;
  for mItem in ARegistry.FindAll(IAtlasHoverValueSource) do
    if Supports(mItem, IAtlasHoverValueSource, mSource) then
    begin
      Result := mSource.HoverValue(AExpression, ATypeChain, AText);
      if Result <> '' then
        Exit;
    end;
end;

end.
