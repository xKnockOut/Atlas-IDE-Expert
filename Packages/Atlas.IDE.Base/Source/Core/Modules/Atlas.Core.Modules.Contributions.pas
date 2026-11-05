unit Atlas.Core.Modules.Contributions;

// Beiträge der Module einsammeln (#1455, Regel 2 und 4): Base fragt die
// Registry bei Bedarf nach allen bereitgestellten Quellen, statt sie einmal
// beim Start zu lesen. So erscheinen und verschwinden Befehle, Menüeinträge
// und Hörer mit ihrem Modul. Ein Fehler in einem Beitrag hält die übrigen nicht
// an; ApplySettings und ThemeChanged liefern die Fehler als
// „Interface: Klasse: Meldung“.
// Es zählen nur Beiträge laufender Module (IsActive): Ein über seinen
// Schalter gestopptes Modul (#1454) bleibt angemeldet, zeigt aber keine
// Befehle, Menüeinträge und Tasten mehr und hört nichts. Beiträge ohne
// angemeldetes Modul als Besitzer (Base selbst) zählen immer.

interface

uses
  System.SysUtils,
  Atlas.Core.Modules.Contract;

type
  TAtlasModuleContributions = class
  public
    /// <summary>Unter AIID bereitgestellte Objekte laufender Module (und solche ohne Modul) in Reihenfolge der
    /// Bereitstellung; ohne Registry leer.</summary>
    class function Active(const ARegistry: IAtlasModuleRegistry; const AIID: TGUID): TArray<IInterface>; static;
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
    /// <summary>Eintrag ohne Befehl mit der Kennung AId an APlace (Caption gesetzt); False ohne.</summary>
    class function FindMenuEntry(const ARegistry: IAtlasModuleRegistry; APlace: TAtlasMenuPlace; const AId: string;
      out AEntry: TAtlasMenuEntry): Boolean; static;
    /// <summary>Tastenkürzel aller Module; Einträge ohne Taste (0) oder ohne Attempt und Run fehlen.</summary>
    class function Keys(const ARegistry: IAtlasModuleRegistry): TArray<TAtlasModuleKey>; static;
    class function EditorViewActivated(const ARegistry: IAtlasModuleRegistry): TArray<string>; static;
    class function ApplySettings(const ARegistry: IAtlasModuleRegistry): TArray<string>; static;
    class function ThemeChanged(const ARegistry: IAtlasModuleRegistry): TArray<string>; static;
    /// <summary>Erster nicht leerer Beitrag; '' ohne.</summary>
    class function HoverValue(const ARegistry: IAtlasModuleRegistry; const AExpression: string;
      const ATypeChain: TArray<string>; const AText: string): string; static;
  end;

implementation

uses
  Atlas.Text.LogMarks;

class function TAtlasModuleContributions.Active(const ARegistry: IAtlasModuleRegistry;
  const AIID: TGUID): TArray<IInterface>;
var
  mItem: TAtlasProvided;
  mModule: IAtlasModule;
begin
  Result := nil;
  if ARegistry = nil then
  begin
    Exit;
  end;
  for mItem in ARegistry.Provisions(AIID) do
  begin
    if not ARegistry.FindModule(mItem.OwnerId, mModule) or mModule.IsActive then
    begin
      Result := Result + [mItem.Instance];
    end;
  end;
end;

class function TAtlasModuleContributions.Commands(const ARegistry: IAtlasModuleRegistry): TArray<TAtlasModuleCommand>;
var
  mItem: IInterface;
  mSource: IAtlasCommandSource;
begin
  Result := nil;
  if ARegistry = nil then
  begin
    Exit;
  end;
  for mItem in Active(ARegistry, IAtlasCommandSource) do
  begin
    if Supports(mItem, IAtlasCommandSource, mSource) then
    begin
      Result := Result + mSource.Commands;
    end;
  end;
end;

class function TAtlasModuleContributions.FindCommand(const ARegistry: IAtlasModuleRegistry; const AId: string;
  out ACommand: TAtlasModuleCommand): Boolean;
var
  mCommand: TAtlasModuleCommand;
begin
  Result := False;
  ACommand := Default(TAtlasModuleCommand);
  for mCommand in Commands(ARegistry) do
  begin
    if SameText(mCommand.Id, AId) then
    begin
      ACommand := mCommand;
      Exit(True);
    end;
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
  begin
    Exit;
  end;
  for mItem in Active(ARegistry, IAtlasMenuSource) do
  begin
    if Supports(mItem, IAtlasMenuSource, mSource) then
    begin
      for mEntry in mSource.MenuEntries do
      begin
        if mEntry.Place = APlace then
        begin
          Result := Result + [mEntry];
        end;
      end;
    end;
  end;
end;

class function TAtlasModuleContributions.FindMenuEntry(const ARegistry: IAtlasModuleRegistry;
  APlace: TAtlasMenuPlace; const AId: string; out AEntry: TAtlasMenuEntry): Boolean;
var
  mEntry: TAtlasMenuEntry;
begin
  Result := False;
  AEntry := Default(TAtlasMenuEntry);
  for mEntry in MenuEntries(ARegistry, APlace) do
  begin
    if (mEntry.Caption <> '') and SameText(mEntry.CommandId, AId) then
    begin
      AEntry := mEntry;
      Exit(True);
    end;
  end;
end;

class function TAtlasModuleContributions.Keys(const ARegistry: IAtlasModuleRegistry): TArray<TAtlasModuleKey>;
var
  mItem: IInterface;
  mSource: IAtlasKeySource;
  mKey: TAtlasModuleKey;
begin
  Result := nil;
  if ARegistry = nil then
  begin
    Exit;
  end;
  for mItem in Active(ARegistry, IAtlasKeySource) do
  begin
    if Supports(mItem, IAtlasKeySource, mSource) then
    begin
      for mKey in mSource.Keys do
      begin
        if (mKey.Key <> 0) and (Assigned(mKey.Attempt) or Assigned(mKey.Run)) then
        begin
          Result := Result + [mKey];
        end;
      end;
    end;
  end;
end;

class function TAtlasModuleContributions.EditorViewActivated(const ARegistry: IAtlasModuleRegistry): TArray<string>;
var
  mItem: IInterface;
  mListener: IAtlasFollowsEditorView;
begin
  Result := nil;
  if ARegistry = nil then
  begin
    Exit;
  end;
  for mItem in Active(ARegistry, IAtlasFollowsEditorView) do
  begin
    if Supports(mItem, IAtlasFollowsEditorView, mListener) then
      try
        mListener.EditorViewActivated;
      except
        on mError: Exception do
          Result := Result + ['IAtlasFollowsEditorView: ' + mError.ClassName + ': ' + TLogMarks.Text(mError.Message)];
      end;
  end;
end;

class function TAtlasModuleContributions.ApplySettings(const ARegistry: IAtlasModuleRegistry): TArray<string>;
var
  mItem: IInterface;
  mListener: IAtlasAppliesSettings;
begin
  Result := nil;
  if ARegistry = nil then
  begin
    Exit;
  end;
  for mItem in Active(ARegistry, IAtlasAppliesSettings) do
  begin
    if Supports(mItem, IAtlasAppliesSettings, mListener) then
      try
        mListener.ApplySettings;
      except
        on mError: Exception do
          Result := Result + ['IAtlasAppliesSettings: ' + mError.ClassName + ': ' + TLogMarks.Text(mError.Message)];
      end;
  end;
end;

class function TAtlasModuleContributions.ThemeChanged(const ARegistry: IAtlasModuleRegistry): TArray<string>;
var
  mItem: IInterface;
  mListener: IAtlasFollowsTheme;
begin
  Result := nil;
  if ARegistry = nil then
  begin
    Exit;
  end;
  for mItem in Active(ARegistry, IAtlasFollowsTheme) do
  begin
    if Supports(mItem, IAtlasFollowsTheme, mListener) then
      try
        mListener.ThemeChanged;
      except
        on mError: Exception do
          Result := Result + ['IAtlasFollowsTheme: ' + mError.ClassName + ': ' + TLogMarks.Text(mError.Message)];
      end;
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
  begin
    Exit;
  end;
  for mItem in Active(ARegistry, IAtlasHoverValueSource) do
  begin
    if Supports(mItem, IAtlasHoverValueSource, mSource) then
    begin
      Result := mSource.HoverValue(AExpression, ATypeChain, AText);
      if Result <> '' then
      begin
        Exit;
      end;
    end;
  end;
end;

end.
