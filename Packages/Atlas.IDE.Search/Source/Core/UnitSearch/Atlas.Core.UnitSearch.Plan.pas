unit Atlas.Core.UnitSearch.Plan;

// Entscheidungen des Fensters „Units suchen“ (#777, #786), ohne VCL und Open
// Tools API. Atlas.IDE.UnitSearch.Commands und Atlas.IDE.UnitSearch.Actions
// hängen sich an die Aktionen der IDE, öffnen das Fenster und rufen den
// Server; was sie dabei entscheiden, steht hier:
// - Aktion der IDE je Modus (Name und Ersatztaste), ob Atlas sie übernimmt
//   und ob ein Tastendruck zum Atlas-Fenster oder zum Dialog der IDE geht.
// - Ob ein offenes Fenster bleibt, Gruppe, aktives Projekt und Wurzel, die
//   Zielunit für „Unit verwenden“.
// - Ziele für „In uses aufnehmen“, Namen ohne Include-Dateien, Liste der
//   Namen, geöffnete Einträge, Argumente der Vorschau und von addUses.

{$SCOPEDENUMS ON}

interface

uses
  Atlas.Core.UnitSearch.Model,
  Atlas.Core.UnitSearch.UseUnit;

type
  TAtlasUnitSearchPlan = record
  public
    /// <summary>Name der IDE-Aktion des Modus („Units“, „Unit verwenden“, „Formulare“).</summary>
    class function IdeActionName(AMode: TAtlasUnitSearchMode): string; static;
    /// <summary>Standardtaste der IDE-Aktion des Modus, als Ersatz, wenn der Name fehlt.</summary>
    class function IdeActionKey(AMode: TAtlasUnitSearchMode): string; static;
    /// <summary>Übernimmt Atlas die Aktion des Modus? Je Modus die Einstellung unitSearch.replace….</summary>
    class function Replaces(AMode: TAtlasUnitSearchMode; ASearch, AUseUnit, AForms: Boolean): Boolean; static;
    /// <summary>Geht der Tastendruck an Atlas? Eingeschaltet, übernommen, ohne Umschalttaste, nicht abgeschaltet.
    /// </summary>
    class function TakesAction(AEnabled, AReplaces, AShift, ADisabled: Boolean): Boolean; static;
    /// <summary>Bleibt das offene Fenster (Modus ACurrentMode, Ziel ACurrentTarget)? Gleicher Modus und bei
    /// „Unit verwenden“ dieselbe Unit.</summary>
    class function KeepsWindow(ACurrentMode, AMode: TAtlasUnitSearchMode; const ACurrentTarget,
      ATarget: string): Boolean; static;
    /// <summary>Gruppe (AGroupFile, sonst das Projekt AProjectFile), Name des aktiven Projekts und Wurzel.</summary>
    class procedure GroupInfo(const AGroupFile, AProjectFile: string; out AGroup, AActiveProject, ARoot: string);
      static;
    /// <summary>Zielunit für „Unit verwenden“: Name von ATargetFile; '' in anderen Modi.</summary>
    class function TargetUnit(AMode: TAtlasUnitSearchMode; const ATargetFile: string): string; static;
    /// <summary>Kann AFileName uses aufnehmen (.pas, .dpr, .dpk)?</summary>
    class function UsesTarget(const AFileName: string): Boolean; static;
    /// <summary>Namen der Einträge ohne Include-Dateien.</summary>
    class function UsesNames(const AEntries: TArray<TAtlasUnitEntry>): TArray<string>; static;
    /// <summary>Namen der Einträge, mit Komma getrennt.</summary>
    class function UnitList(const AEntries: TArray<TAtlasUnitEntry>): string; static;
    /// <summary>IsOpen je Eintrag: Datei unter AOpenFiles (Groß/klein egal).</summary>
    class procedure MarkOpen(var AEntries: TAtlasUnitEntries; const AOpenFiles: TArray<string>); static;
    /// <summary>Argumente von atlas.server.unitPreview: Uri und die gewünschten Teile.</summary>
    class function PreviewArguments(const AUri: string; AForm, AUsedBy: Boolean): string; static;
    /// <summary>Argumente von atlas.server.addUses ohne Abschnitt: Uri und Namen.</summary>
    class function AddUsesArguments(const AUri: string; const ANames: TArray<string>): string; static;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  System.Generics.Collections;

{ TAtlasUnitSearchPlan }

class function TAtlasUnitSearchPlan.IdeActionName(AMode: TAtlasUnitSearchMode): string;
begin
  case AMode of
    TAtlasUnitSearchMode.UseUnit:
      Result := 'FileUseUnitCommand';
    TAtlasUnitSearchMode.Forms:
      Result := 'ViewFormCommand';
  else
    Result := 'ViewUnitCommand';
  end;
end;

class function TAtlasUnitSearchPlan.IdeActionKey(AMode: TAtlasUnitSearchMode): string;
begin
  case AMode of
    TAtlasUnitSearchMode.UseUnit:
      Result := 'Alt+F11';
    TAtlasUnitSearchMode.Forms:
      Result := 'Shift+F12';
  else
    Result := 'Ctrl+F12';
  end;
end;

class function TAtlasUnitSearchPlan.Replaces(AMode: TAtlasUnitSearchMode; ASearch, AUseUnit, AForms: Boolean): Boolean;
begin
  case AMode of
    TAtlasUnitSearchMode.UseUnit:
      Result := AUseUnit;
    TAtlasUnitSearchMode.Forms:
      Result := AForms;
  else
    Result := ASearch;
  end;
end;

class function TAtlasUnitSearchPlan.TakesAction(AEnabled, AReplaces, AShift, ADisabled: Boolean): Boolean;
begin
  Result := AEnabled and AReplaces and not AShift and not ADisabled;
end;

class function TAtlasUnitSearchPlan.KeepsWindow(ACurrentMode, AMode: TAtlasUnitSearchMode; const ACurrentTarget,
  ATarget: string): Boolean;
begin
  Result := (ACurrentMode = AMode) and ((AMode <> TAtlasUnitSearchMode.UseUnit) or SameText(ACurrentTarget, ATarget));
end;

class procedure TAtlasUnitSearchPlan.GroupInfo(const AGroupFile, AProjectFile: string; out AGroup, AActiveProject,
  ARoot: string);
begin
  AGroup := AGroupFile;
  AActiveProject := '';
  ARoot := '';
  if AProjectFile <> '' then
  begin
    AActiveProject := ChangeFileExt(ExtractFileName(AProjectFile), '');
    if AGroup = '' then
    begin
      AGroup := AProjectFile;
    end;
  end;
  if AGroup <> '' then
  begin
    ARoot := ExtractFileDir(AGroup);
  end;
end;

class function TAtlasUnitSearchPlan.TargetUnit(AMode: TAtlasUnitSearchMode; const ATargetFile: string): string;
begin
  Result := '';
  if AMode = TAtlasUnitSearchMode.UseUnit then
  begin
    Result := ChangeFileExt(ExtractFileName(ATargetFile), '');
  end;
end;

class function TAtlasUnitSearchPlan.UsesTarget(const AFileName: string): Boolean;
var
  mExtension: string;
begin
  mExtension := ExtractFileExt(AFileName);
  Result := (AFileName <> '') and (SameText(mExtension, '.pas') or SameText(mExtension, '.dpr') or
    SameText(mExtension, '.dpk'));
end;

class function TAtlasUnitSearchPlan.UsesNames(const AEntries: TArray<TAtlasUnitEntry>): TArray<string>;
var
  mEntry: TAtlasUnitEntry;
begin
  Result := nil;
  for mEntry in AEntries do
  begin
    if mEntry.Kind <> TAtlasUnitKind.Include then
    begin
      Result := Result + [mEntry.Name];
    end;
  end;
end;

class function TAtlasUnitSearchPlan.UnitList(const AEntries: TArray<TAtlasUnitEntry>): string;
var
  mEntry: TAtlasUnitEntry;
begin
  Result := '';
  for mEntry in AEntries do
  begin
    if Result <> '' then
    begin
      Result := Result + ', ';
    end;
    Result := Result + mEntry.Name;
  end;
end;

class procedure TAtlasUnitSearchPlan.MarkOpen(var AEntries: TAtlasUnitEntries; const AOpenFiles: TArray<string>);
var
  mFiles: TDictionary<string, Boolean>;
  mFileName: string;
  mIndex: Integer;
begin
  mFiles := TDictionary<string, Boolean>.Create;
  try
    for mFileName in AOpenFiles do
    begin
      mFiles.AddOrSetValue(LowerCase(mFileName), True);
    end;
    for mIndex := 0 to High(AEntries) do
    begin
      AEntries[mIndex].IsOpen := mFiles.ContainsKey(LowerCase(AEntries[mIndex].FileName));
    end;
  finally
    mFiles.Free;
  end;
end;

class function TAtlasUnitSearchPlan.PreviewArguments(const AUri: string; AForm, AUsedBy: Boolean): string;
var
  mArguments: TJSONArray;
  mFlags: TJSONObject;
begin
  mArguments := TJSONArray.Create;
  try
    mArguments.Add(AUri);
    mFlags := TJSONObject.Create;
    mFlags.AddPair('form', TJSONBool.Create(AForm));
    mFlags.AddPair('usedBy', TJSONBool.Create(AUsedBy));
    mArguments.Add(mFlags);
    Result := mArguments.ToJSON;
  finally
    mArguments.Free;
  end;
end;

class function TAtlasUnitSearchPlan.AddUsesArguments(const AUri: string; const ANames: TArray<string>): string;
var
  mValues, mNames: TJSONArray;
  mName: string;
begin
  mValues := TJSONArray.Create;
  try
    mValues.Add(AUri);
    mNames := TJSONArray.Create;
    for mName in ANames do
    begin
      mNames.Add(mName);
    end;
    mValues.AddElement(mNames);
    Result := mValues.ToJSON;
  finally
    mValues.Free;
  end;
end;

end.
