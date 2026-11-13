unit Atlas.Core.Debug.BreakpointSets;

// Haltepunkt-Sätze (#586), ohne VCL und Open Tools API: benannte Sätze von
// Quelltext-Haltepunkten, zwischen denen man wechselt.
// - Ein Satz merkt sich je Haltepunkt Datei, Anker an der Methode
//   (Atlas.Core.Editor.MethodAnchor: Methode, Abstand zur Kopfzeile,
//   Zeilentext mit Nachbarzeilen) und die Eigenschaften (Bedingung,
//   Durchlaufzahl, Gruppe, Aktionen, an/aus). Beim Laden sucht Atlas die
//   Zeile über Methode und Zeilentext; nicht mehr auffindbare meldet es.
// - Ablage je Projekt in <Projektordner>/.atlas/breakpoints/<Name>.json
//   (Format 1, Pfade relativ zum Projektordner mit "/"), damit sich Sätze im
//   Repository teilen lassen. Optional mit Branch: Bei eingeschalteter
//   Kopplung wird der Satz beim Wechsel auf diesen Branch aktiv.
// - Plan bestimmt aus den Haltepunkten der IDE und den aufgelösten Sätzen,
//   was zu tun ist: Haltepunkte des Satzes anlegen bzw. einschalten; beim
//   Wechsel (exklusiv) die Haltepunkte anderer Sätze ausschalten, nicht
//   löschen. Haltepunkte, die zu keinem Satz gehören, bleiben unberührt.
// Verhältnis zu den Haltepunktgruppen der IDE: Gruppen sind Namen an
// Haltepunkten, die Aktionen anderer Haltepunkte (Gruppe ein/aus) schalten;
// sie liegen mit Zeilennummern in der .dsk und überstehen weder Änderungen
// am Quelltext noch das Teilen im Repository. Ein Satz übernimmt die Gruppe
// jedes Haltepunkts als Eigenschaft und lässt sie unverändert.

interface

uses
  System.SysUtils,
  Atlas.Core.Editor.LineAnchor,
  Atlas.Core.Editor.MethodAnchor;

type
  /// <summary>Eigenschaften eines Quelltext-Haltepunkts, wie die IDE sie kennt.</summary>
  TAtlasBreakpointProps = record
    Enabled: Boolean;
    Condition: string;
    PassCount: Integer;
    Group: string;
    DoBreak: Boolean;
    LogMessage: string;
    EvalExpression: string;
    LogResult: Boolean;
    EnableGroup: string;
    DisableGroup: string;
    HandleExceptions: Boolean;
    IgnoreExceptions: Boolean;
    StackFrames: Integer;
    /// <summary>Vorgabe der IDE: an, hält, Ergebnis protokollieren.</summary>
    class function Default: TAtlasBreakpointProps; static;
  end;

  TAtlasBreakpointSetEntry = record
    /// <summary>Vollständiger Pfad.</summary>
    FileName: string;
    Anchor: TAtlasMethodAnchor;
    Props: TAtlasBreakpointProps;
  end;

  TAtlasBreakpointSetEntries = TArray<TAtlasBreakpointSetEntry>;

  TAtlasBreakpointSet = record
    Name: string;
    /// <summary>Gekoppelter Branch (Git) bzw. Pfad (SVN); '' ohne.</summary>
    Branch: string;
    Entries: TAtlasBreakpointSetEntries;
  end;

  TAtlasBreakpointSetList = TArray<TAtlasBreakpointSet>;

  /// <summary>Quelltext-Haltepunkt der IDE für den Plan.</summary>
  TAtlasBreakpointPlace = record
    FileName: string;
    /// <summary>0-basiert.</summary>
    Line: Integer;
    Enabled: Boolean;
    class function Create(const AFileName: string; ALine: Integer; AEnabled: Boolean): TAtlasBreakpointPlace; static;
  end;

  TAtlasBreakpointPlaces = TArray<TAtlasBreakpointPlace>;

  /// <summary>Eintrag eines Satzes mit der Zeile im aktuellen Text.</summary>
  TAtlasResolvedBreakpoint = record
    Entry: TAtlasBreakpointSetEntry;
    /// <summary>Gefundene Zeile (0-basiert); bei Orphaned die bisherige.</summary>
    Line: Integer;
    Match: TAtlasLineMatch;
    function Found: Boolean;
  end;

  TAtlasResolvedBreakpoints = TArray<TAtlasResolvedBreakpoint>;

  /// <summary>Text einer Datei (Editor oder Platte); False, wenn sie nicht lesbar ist.</summary>
  TAtlasBreakpointTextFunc = reference to function(const AFileName: string; out AText: string): Boolean;

  {$SCOPEDENUMS ON}
  /// <summary>Enable/Disable: Haltepunkt Index der IDE schalten; Create: Entry an Line anlegen; Missing: Entry
  /// nicht gefunden.</summary>
  TAtlasBreakpointSetActionKind = (Enable, Disable, Create, Missing);
  {$SCOPEDENUMS OFF}

  TAtlasBreakpointSetAction = record
    Kind: TAtlasBreakpointSetActionKind;
    /// <summary>Index in den Haltepunkten der IDE (Enable, Disable), sonst -1.</summary>
    Index: Integer;
    Entry: TAtlasBreakpointSetEntry;
    /// <summary>Zeile (0-basiert) für Create bzw. letzte bekannte für Missing.</summary>
    Line: Integer;
  end;

  TAtlasBreakpointSetActions = TArray<TAtlasBreakpointSetAction>;

  TAtlasBreakpointSets = class
  public const
    cFormat = 1;
    cMaxNameLength = 80;
  public
    /// <summary>Ordner der Sätze: .atlas/breakpoints unter AProjectFolder.</summary>
    class function Folder(const AProjectFolder: string): string; static;
    class function FileFor(const AProjectFolder, AName: string): string; static;
    /// <summary>Als Dateiname brauchbar: nicht leer, ohne \ / : * ? " &lt; &gt; |, ohne Punkt am Ende,
    /// höchstens cMaxNameLength Zeichen.</summary>
    class function ValidName(const AName: string): Boolean; static;
    class function ToJson(const ASet: TAtlasBreakpointSet; const AProjectFolder: string): string; static;
    /// <summary>Liest Format 1; Name aus ADefaultName, wenn die Datei keinen nennt. False bei anderem Format oder
    /// kaputtem JSON.</summary>
    class function Parse(const AJson, AProjectFolder, ADefaultName: string; out ASet: TAtlasBreakpointSet): Boolean;
      static;
    /// <summary>Eintrag für einen Haltepunkt an ALine (0-basiert) im Text AText.</summary>
    class function Capture(const AFileName, AText: string; ALine: Integer;
      const AProps: TAtlasBreakpointProps): TAtlasBreakpointSetEntry; static;
    /// <summary>Einträge von ASource, die ATarget noch nicht hat (gleiche Datei und Zeile), hinten anhängen.
    /// </summary>
    class function Merge(const ATarget, ASource: TAtlasBreakpointSet): TAtlasBreakpointSet; static;
    /// <summary>Index des Satzes mit Branch ABranch (ohne Groß-/Kleinschreibung); -1 ohne.</summary>
    class function ForBranch(const ASets: TAtlasBreakpointSetList; const ABranch: string): Integer; static;
    /// <summary>Zeilen der Einträge im aktuellen Text; jede Datei wird einmal gelesen. Nicht lesbare Dateien:
    /// Orphaned.</summary>
    class function Resolve(const AEntries: TAtlasBreakpointSetEntries;
      const AText: TAtlasBreakpointTextFunc): TAtlasResolvedBreakpoints; static;
    /// <summary>Was zu tun ist, um ATarget zu laden. AExclusive (Wechsel): Haltepunkte an Stellen aus AOthers,
    /// die nicht zu ATarget gehören, ausschalten.</summary>
    class function Plan(const ACurrent: TAtlasBreakpointPlaces; const ATarget, AOthers: TAtlasResolvedBreakpoints;
      AExclusive: Boolean): TAtlasBreakpointSetActions; static;
    /// <summary>Gleiche Datei (ohne Groß-/Kleinschreibung, \ und / gleich)?</summary>
    class function SameFile(const A, B: string): Boolean; static;
  end;

implementation

uses
  System.JSON,
  System.Generics.Collections,
  Atlas.Text.Json;

const
  cFolderName = '.atlas';
  cSetsName = 'breakpoints';
  cBadChars = '\/:*?"<>|';

{ TAtlasBreakpointProps }

class function TAtlasBreakpointProps.Default: TAtlasBreakpointProps;
begin
  Result.Enabled := True;
  Result.Condition := '';
  Result.PassCount := 0;
  Result.Group := '';
  Result.DoBreak := True;
  Result.LogMessage := '';
  Result.EvalExpression := '';
  Result.LogResult := True;
  Result.EnableGroup := '';
  Result.DisableGroup := '';
  Result.HandleExceptions := False;
  Result.IgnoreExceptions := False;
  Result.StackFrames := 0;
end;

{ TAtlasBreakpointPlace }

class function TAtlasBreakpointPlace.Create(const AFileName: string; ALine: Integer;
  AEnabled: Boolean): TAtlasBreakpointPlace;
begin
  Result.FileName := AFileName;
  Result.Line := ALine;
  Result.Enabled := AEnabled;
end;

{ TAtlasResolvedBreakpoint }

function TAtlasResolvedBreakpoint.Found: Boolean;
begin
  Result := Match <> TAtlasLineMatch.Orphaned;
end;

{ TAtlasBreakpointSets }

class function TAtlasBreakpointSets.Folder(const AProjectFolder: string): string;
begin
  Result := IncludeTrailingPathDelimiter(AProjectFolder) + cFolderName + PathDelim + cSetsName;
end;

class function TAtlasBreakpointSets.FileFor(const AProjectFolder, AName: string): string;
begin
  Result := Folder(AProjectFolder) + PathDelim + Trim(AName) + '.json';
end;

class function TAtlasBreakpointSets.ValidName(const AName: string): Boolean;
var
  mName: string;
  mCh: Char;
begin
  mName := Trim(AName);
  Result := (mName <> '') and (Length(mName) <= cMaxNameLength) and (mName[Length(mName)] <> '.');
  if not Result then
  begin
    Exit;
  end;
  for mCh in mName do
  begin
    if (Pos(mCh, cBadChars) > 0) or (mCh < ' ') then
    begin
      Exit(False);
    end;
  end;
end;

class function TAtlasBreakpointSets.SameFile(const A, B: string): Boolean;
begin
  Result := SameText(A.Replace('\', '/'), B.Replace('\', '/'));
end;

/// <summary>Pfad für die Datei: relativ zu AFolder, wenn darunter, mit "/".</summary>
function ToStored(const AFileName, AFolder: string): string;
var
  mFolder, mFile: string;
begin
  mFile := AFileName.Replace('\', '/');
  Result := mFile;
  if AFolder = '' then
  begin
    Exit;
  end;
  mFolder := AFolder.Replace('\', '/');
  if not mFolder.EndsWith('/') then
  begin
    mFolder := mFolder + '/';
  end;
  if SameText(Copy(mFile, 1, Length(mFolder)), mFolder) then
  begin
    Result := Copy(mFile, Length(mFolder) + 1, MaxInt);
  end;
end;

/// <summary>Gespeicherter Pfad zurück: relativ zum Projektordner, Trenner des Systems.</summary>
function FromStored(const AStored, AFolder: string): string;
var
  mPath: string;
begin
  mPath := AStored.Replace('/', PathDelim).Replace('\', PathDelim);
  if (AFolder = '') or (ExtractFileDrive(mPath) <> '') or mPath.StartsWith(PathDelim) then
  begin
    Result := mPath;
  end
  else
  begin
    Result := IncludeTrailingPathDelimiter(AFolder.Replace('/', PathDelim).Replace('\', PathDelim)) + mPath;
  end;
end;

procedure AddText(AObject: TJSONObject; const AName, AValue: string);
begin
  if AValue <> '' then
  begin
    AObject.AddPair(AName, AValue);
  end;
end;

function EntryJson(const AEntry: TAtlasBreakpointSetEntry; const AFolder: string): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('file', ToStored(AEntry.FileName, AFolder));
  TAtlasMethodAnchors.AddTo(Result, AEntry.Anchor);
  Result.AddPair('enabled', TJSONBool.Create(AEntry.Props.Enabled));
  AddText(Result, 'condition', AEntry.Props.Condition);
  if AEntry.Props.PassCount > 0 then
  begin
    Result.AddPair('passCount', TJSONNumber.Create(AEntry.Props.PassCount));
  end;
  AddText(Result, 'group', AEntry.Props.Group);
  if not AEntry.Props.DoBreak then
  begin
    Result.AddPair('break', TJSONBool.Create(False));
  end;
  AddText(Result, 'logMessage', AEntry.Props.LogMessage);
  AddText(Result, 'evalExpression', AEntry.Props.EvalExpression);
  if not AEntry.Props.LogResult then
  begin
    Result.AddPair('logResult', TJSONBool.Create(False));
  end;
  AddText(Result, 'enableGroup', AEntry.Props.EnableGroup);
  AddText(Result, 'disableGroup', AEntry.Props.DisableGroup);
  if AEntry.Props.HandleExceptions then
  begin
    Result.AddPair('handleExceptions', TJSONBool.Create(True));
  end;
  if AEntry.Props.IgnoreExceptions then
  begin
    Result.AddPair('ignoreExceptions', TJSONBool.Create(True));
  end;
  if AEntry.Props.StackFrames > 0 then
  begin
    Result.AddPair('stackFrames', TJSONNumber.Create(AEntry.Props.StackFrames));
  end;
end;

function EntryOf(AObject: TJSONObject; const AFolder: string; out AEntry: TAtlasBreakpointSetEntry): Boolean;
begin
  AEntry := Default(TAtlasBreakpointSetEntry);
  AEntry.FileName := TJsonRead.Text(AObject, 'file');
  Result := AEntry.FileName <> '';
  if not Result then
  begin
    Exit;
  end;
  AEntry.FileName := FromStored(AEntry.FileName, AFolder);
  AEntry.Anchor := TAtlasMethodAnchors.ReadFrom(AObject);
  AEntry.Props := TAtlasBreakpointProps.Default;
  AEntry.Props.Enabled := TJsonRead.FlagOr(AObject, 'enabled', True);
  AEntry.Props.Condition := TJsonRead.Text(AObject, 'condition');
  AEntry.Props.PassCount := TJsonRead.IntOr(AObject, 'passCount', 0);
  AEntry.Props.Group := TJsonRead.Text(AObject, 'group');
  AEntry.Props.DoBreak := TJsonRead.FlagOr(AObject, 'break', True);
  AEntry.Props.LogMessage := TJsonRead.Text(AObject, 'logMessage');
  AEntry.Props.EvalExpression := TJsonRead.Text(AObject, 'evalExpression');
  AEntry.Props.LogResult := TJsonRead.FlagOr(AObject, 'logResult', True);
  AEntry.Props.EnableGroup := TJsonRead.Text(AObject, 'enableGroup');
  AEntry.Props.DisableGroup := TJsonRead.Text(AObject, 'disableGroup');
  AEntry.Props.HandleExceptions := TJsonRead.Flag(AObject, 'handleExceptions');
  AEntry.Props.IgnoreExceptions := TJsonRead.Flag(AObject, 'ignoreExceptions');
  AEntry.Props.StackFrames := TJsonRead.IntOr(AObject, 'stackFrames', 0);
end;

class function TAtlasBreakpointSets.ToJson(const ASet: TAtlasBreakpointSet; const AProjectFolder: string): string;
var
  mRoot: TJSONObject;
  mList: TJSONArray;
  mEntry: TAtlasBreakpointSetEntry;
begin
  mRoot := TJSONObject.Create;
  try
    mRoot.AddPair('format', TJSONNumber.Create(cFormat));
    mRoot.AddPair('name', Trim(ASet.Name));
    AddText(mRoot, 'branch', ASet.Branch);
    mList := TJSONArray.Create;
    mRoot.AddPair('breakpoints', mList);
    for mEntry in ASet.Entries do
    begin
      mList.AddElement(EntryJson(mEntry, AProjectFolder));
    end;
    Result := mRoot.ToJSON([]);
  finally
    mRoot.Free;
  end;
end;

class function TAtlasBreakpointSets.Parse(const AJson, AProjectFolder, ADefaultName: string;
  out ASet: TAtlasBreakpointSet): Boolean;
var
  mValue: TJSONValue;
  mRoot: TJSONObject;
  mList: TJSONArray;
  mIndex: Integer;
  mEntry: TAtlasBreakpointSetEntry;
begin
  ASet := Default(TAtlasBreakpointSet);
  Result := False;
  mValue := TJSONObject.ParseJSONValue(AJson);
  try
    if not (mValue is TJSONObject) then
    begin
      Exit;
    end;
    mRoot := TJSONObject(mValue);
    if TJsonRead.IntOr(mRoot, 'format', 0) <> cFormat then
    begin
      Exit;
    end;
    ASet.Name := TJsonRead.TrimmedText(mRoot, 'name');
    if ASet.Name = '' then
    begin
      ASet.Name := ADefaultName;
    end;
    ASet.Branch := TJsonRead.TrimmedText(mRoot, 'branch');
    mList := TJsonRead.Items(mRoot, 'breakpoints');
    if mList <> nil then
    begin
      for mIndex := 0 to mList.Count - 1 do
      begin
        if (mList.Items[mIndex] is TJSONObject) and EntryOf(TJSONObject(mList.Items[mIndex]), AProjectFolder,
          mEntry) then
        begin
          ASet.Entries := ASet.Entries + [mEntry];
        end;
      end;
    end;
    Result := True;
  finally
    mValue.Free;
  end;
end;

class function TAtlasBreakpointSets.Capture(const AFileName, AText: string; ALine: Integer;
  const AProps: TAtlasBreakpointProps): TAtlasBreakpointSetEntry;
begin
  Result.FileName := AFileName;
  Result.Anchor := TAtlasMethodAnchors.Capture(AText, ALine);
  Result.Props := AProps;
end;

function HasEntryAt(const ASet: TAtlasBreakpointSet; const AEntry: TAtlasBreakpointSetEntry): Boolean;
var
  mEntry: TAtlasBreakpointSetEntry;
begin
  Result := False;
  for mEntry in ASet.Entries do
  begin
    if TAtlasBreakpointSets.SameFile(mEntry.FileName, AEntry.FileName) and (mEntry.Anchor.Line = AEntry.Anchor.Line)
    then
    begin
      Exit(True);
    end;
  end;
end;

class function TAtlasBreakpointSets.Merge(const ATarget, ASource: TAtlasBreakpointSet): TAtlasBreakpointSet;
var
  mEntry: TAtlasBreakpointSetEntry;
begin
  Result := ATarget;
  Result.Entries := Copy(ATarget.Entries);
  for mEntry in ASource.Entries do
  begin
    if not HasEntryAt(Result, mEntry) then
    begin
      Result.Entries := Result.Entries + [mEntry];
    end;
  end;
end;

class function TAtlasBreakpointSets.ForBranch(const ASets: TAtlasBreakpointSetList; const ABranch: string): Integer;
var
  mIndex: Integer;
begin
  Result := -1;
  if Trim(ABranch) = '' then
  begin
    Exit;
  end;
  for mIndex := 0 to High(ASets) do
  begin
    if SameText(ASets[mIndex].Branch, Trim(ABranch)) then
    begin
      Exit(mIndex);
    end;
  end;
end;

class function TAtlasBreakpointSets.Resolve(const AEntries: TAtlasBreakpointSetEntries;
  const AText: TAtlasBreakpointTextFunc): TAtlasResolvedBreakpoints;
var
  mTexts: TDictionary<string, TAtlasMethodAnchorText>;
  mReadable: TDictionary<string, Boolean>;
  mIndex: Integer;
  mKey, mText: string;
  mParsed: TAtlasMethodAnchorText;
  mOk: Boolean;
begin
  SetLength(Result, Length(AEntries));
  mTexts := TDictionary<string, TAtlasMethodAnchorText>.Create;
  mReadable := TDictionary<string, Boolean>.Create;
  try
    for mIndex := 0 to High(AEntries) do
    begin
      Result[mIndex].Entry := AEntries[mIndex];
      Result[mIndex].Line := AEntries[mIndex].Anchor.Line;
      Result[mIndex].Match := TAtlasLineMatch.Orphaned;
      mKey := AnsiLowerCase(AEntries[mIndex].FileName.Replace('\', '/'));
      if not mReadable.TryGetValue(mKey, mOk) then
      begin
        mOk := Assigned(AText) and AText(AEntries[mIndex].FileName, mText);
        mReadable.Add(mKey, mOk);
        if mOk then
        begin
          mTexts.Add(mKey, TAtlasMethodAnchorText.Create(mText));
        end;
      end;
      if mOk and mTexts.TryGetValue(mKey, mParsed) then
      begin
        Result[mIndex].Match := TAtlasMethodAnchors.Find(mParsed, AEntries[mIndex].Anchor, Result[mIndex].Line);
      end;
    end;
  finally
    mReadable.Free;
    mTexts.Free;
  end;
end;

function IndexAt(const ACurrent: TAtlasBreakpointPlaces; const AFileName: string; ALine: Integer): Integer;
var
  mIndex: Integer;
begin
  Result := -1;
  for mIndex := 0 to High(ACurrent) do
  begin
    if (ACurrent[mIndex].Line = ALine) and TAtlasBreakpointSets.SameFile(ACurrent[mIndex].FileName, AFileName) then
    begin
      Exit(mIndex);
    end;
  end;
end;

function Action(AKind: TAtlasBreakpointSetActionKind; AIndex: Integer; const AEntry: TAtlasBreakpointSetEntry;
  ALine: Integer): TAtlasBreakpointSetAction;
begin
  Result.Kind := AKind;
  Result.Index := AIndex;
  Result.Entry := AEntry;
  Result.Line := ALine;
end;

function InTarget(const ATarget: TAtlasResolvedBreakpoints; const AFileName: string; ALine: Integer): Boolean;
var
  mItem: TAtlasResolvedBreakpoint;
begin
  Result := False;
  for mItem in ATarget do
  begin
    if mItem.Found and (mItem.Line = ALine) and TAtlasBreakpointSets.SameFile(mItem.Entry.FileName, AFileName) then
    begin
      Exit(True);
    end;
  end;
end;

/// <summary>Aktion für einen gefundenen Eintrag des Zielsatzes an ACurrent[AIndex]: Ein- oder Ausschalten, wenn der
/// Zustand abweicht; False, wenn nichts zu tun ist.</summary>
function ToggleAction(const ACurrent: TAtlasBreakpointPlaces; AIndex: Integer; const AItem: TAtlasResolvedBreakpoint;
  out AAction: TAtlasBreakpointSetAction): Boolean;
begin
  Result := AItem.Entry.Props.Enabled <> ACurrent[AIndex].Enabled;
  if not Result then
  begin
    AAction := Default(TAtlasBreakpointSetAction);
  end
  else if AItem.Entry.Props.Enabled then
  begin
    AAction := Action(TAtlasBreakpointSetActionKind.Enable, AIndex, AItem.Entry, AItem.Line);
  end
  else
  begin
    AAction := Action(TAtlasBreakpointSetActionKind.Disable, AIndex, AItem.Entry, AItem.Line);
  end;
end;

/// <summary>Aktionen für den Zielsatz; ADone markiert die schon behandelten Haltepunkte von ACurrent.</summary>
function PlanTarget(const ACurrent: TAtlasBreakpointPlaces; const ATarget: TAtlasResolvedBreakpoints;
  var ADone: TArray<Boolean>): TAtlasBreakpointSetActions;
var
  mItem: TAtlasResolvedBreakpoint;
  mIndex: Integer;
  mCreated: TAtlasBreakpointPlaces;
  mAction: TAtlasBreakpointSetAction;
begin
  Result := nil;
  mCreated := nil;
  for mItem in ATarget do
  begin
    mIndex := -1;
    if mItem.Found then
    begin
      mIndex := IndexAt(ACurrent, mItem.Entry.FileName, mItem.Line);
    end;
    if not mItem.Found then
    begin
      Result := Result + [Action(TAtlasBreakpointSetActionKind.Missing, -1, mItem.Entry, mItem.Line)];
    end
    else if mIndex < 0 then
    begin
      // Zwei Einträge auf derselben Zeile: nur einmal anlegen.
      if IndexAt(mCreated, mItem.Entry.FileName, mItem.Line) < 0 then
      begin
        mCreated := mCreated + [TAtlasBreakpointPlace.Create(mItem.Entry.FileName, mItem.Line, True)];
        Result := Result + [Action(TAtlasBreakpointSetActionKind.Create, -1, mItem.Entry, mItem.Line)];
      end;
    end
    else if not ADone[mIndex] then
    begin
      ADone[mIndex] := True;
      if ToggleAction(ACurrent, mIndex, mItem, mAction) then
      begin
        Result := Result + [mAction];
      end;
    end;
  end;
end;

/// <summary>Ausschalten, was nur in anderen Sätzen steht und noch an ist.</summary>
function PlanOthers(const ACurrent: TAtlasBreakpointPlaces; const ATarget, AOthers: TAtlasResolvedBreakpoints;
  var ADone: TArray<Boolean>): TAtlasBreakpointSetActions;
var
  mItem: TAtlasResolvedBreakpoint;
  mIndex: Integer;
begin
  Result := nil;
  for mItem in AOthers do
  begin
    if not mItem.Found or InTarget(ATarget, mItem.Entry.FileName, mItem.Line) then
    begin
      Continue;
    end;
    mIndex := IndexAt(ACurrent, mItem.Entry.FileName, mItem.Line);
    if (mIndex >= 0) and not ADone[mIndex] and ACurrent[mIndex].Enabled then
    begin
      ADone[mIndex] := True;
      Result := Result + [Action(TAtlasBreakpointSetActionKind.Disable, mIndex, mItem.Entry, mItem.Line)];
    end;
  end;
end;

class function TAtlasBreakpointSets.Plan(const ACurrent: TAtlasBreakpointPlaces;
  const ATarget, AOthers: TAtlasResolvedBreakpoints; AExclusive: Boolean): TAtlasBreakpointSetActions;
var
  mDone: TArray<Boolean>;
begin
  SetLength(mDone, Length(ACurrent));
  Result := PlanTarget(ACurrent, ATarget, mDone);
  if AExclusive then
  begin
    Result := Result + PlanOthers(ACurrent, ATarget, AOthers, mDone);
  end;
end;

end.
