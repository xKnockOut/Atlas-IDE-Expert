unit Atlas.Core.Designer.Undo;

// Rückgängig im Formular-Designer (#1887, experimentell), Teil ohne VCL und
// Open Tools API. Nach jeder Änderung im Designer merkt sich Atlas den
// Formulartext (wie beim Speichern) in TAtlasFormUndoHistory, höchstens
// designer.undoSteps Schritte je Formular, nur im Speicher.
// - Zurückladen: Die ToolsAPI kann keinen Formulartext in einen offenen
//   Designer laden. TAtlasFormUndo.Plan vergleicht darum den aktuellen mit
//   dem gewünschten Stand und plant die Schritte für die IDE-Schicht:
//   Komponenten löschen, umbenennen und neu anlegen (je Objekt mit Klasse,
//   Elternelement und eigenen Werten, Eltern vor Kindern), dann je
//   Komponente Werte setzen (als kleiner Formulartext „object … end“ für
//   TReader, so gehen auch Kollektionen, Listen und Binärdaten), auf die
//   Vorgabe zurücksetzen und Ereignisse zuordnen.
// - Geerbte Komponenten und Komponenten in eingebetteten Frames lassen sich
//   nicht löschen oder anlegen; der Plan nennt sie unter Skipped.
// - Describe liefert den lesbaren Text eines Schritts („Panel1.Align:
//   alNone → alClient“, „btnOK verschoben (312, 410) → (296, 410)“); die
//   Wörter kommen von außen (Sprache der Oberfläche).

interface

type
  /// <summary>Gespeicherter Wert eines Objekts im Formulartext.</summary>
  TAtlasUndoValue = record
    /// <summary>Pfad wie in der Datei, auch Font.Name oder Lines.Strings.</summary>
    Path: string;
    /// <summary>Wert als DFM-Text; mehrzeilige Werte mit #10 verbunden.</summary>
    Value: string;
    /// <summary>Zeilen wie in der Datei, ohne die Einrückung der Eigenschaft.</summary>
    Lines: TArray<string>;
    /// <summary>Ereignis (OnClick = Button1Click).</summary>
    IsEvent: Boolean;
  end;

  /// <summary>Objekt im Formulartext.</summary>
  TAtlasUndoObject = record
    /// <summary>'' = das Formular selbst; in eingebetteten Frames „Frame1.Button1“.</summary>
    Key: string;
    Name: string;
    TypeName: string;
    /// <summary>object, inherited oder inline (klein geschrieben).</summary>
    Kind: string;
    /// <summary>Schlüssel des umschließenden Objekts im Text; '' auf dem Formular.</summary>
    ParentKey: string;
    Values: TArray<TAtlasUndoValue>;
    /// <summary>Index des Werts APath ohne Groß-/Kleinschreibung; -1 ohne ihn.</summary>
    function IndexOf(const APath: string): Integer;
    /// <summary>Wert zu APath; '' ohne ihn.</summary>
    function ValueOf(const APath: string): string;
    /// <summary>Darf Atlas es löschen und anlegen? Nur „object“ außerhalb eingebetteter Frames.</summary>
    function Plain: Boolean;
  end;

  TAtlasUndoEvent = record
    Path: string;
    /// <summary>Name des Handlers; '' = Zuordnung entfernen.</summary>
    Handler: string;
  end;

  /// <summary>Was an einer Komponente zu tun ist (anlegen oder ändern).</summary>
  TAtlasUndoComponent = record
    Key: string;
    Name: string;
    TypeName: string;
    /// <summary>Elternelement im Zielstand ('' = Formular).</summary>
    ParentKey: string;
    /// <summary>Kleiner Formulartext „object Name: TTyp … end“ mit den zu setzenden Werten; '' ohne.</summary>
    Text: string;
    /// <summary>Pfade, die Text setzt.</summary>
    Paths: TArray<string>;
    /// <summary>Pfade, die auf die Vorgabe zurückgehen.</summary>
    Resets: TArray<string>;
    Events: TArray<TAtlasUndoEvent>;
  end;

  TAtlasUndoRename = record
    OldKey: string;
    NewName: string;
  end;

  TAtlasUndoPlan = record
    /// <summary>Zu löschende Komponenten (nur die obersten eines Teilbaums).</summary>
    Deletes: TArray<string>;
    Renames: TArray<TAtlasUndoRename>;
    /// <summary>Neu anzulegen, Eltern vor Kindern; ParentKey besteht dann schon.</summary>
    Creates: TArray<TAtlasUndoComponent>;
    Changes: TArray<TAtlasUndoComponent>;
    /// <summary>Was sich nicht herstellen lässt (geerbt, in einem Frame).</summary>
    Skipped: TArray<string>;
    function IsEmpty: Boolean;
    /// <summary>Wird gelöscht, umbenannt oder angelegt?</summary>
    function Structural: Boolean;
  end;

  /// <summary>Formate für Describe in der Sprache der Oberfläche.</summary>
  TAtlasUndoWords = record
    /// <summary>Name, alte Lage, neue Lage: '%s verschoben (%s, %s) → (%s, %s)'.</summary>
    Moved: string;
    /// <summary>Name, alte Größe, neue Größe: '%s Größe (%s, %s) → (%s, %s)'.</summary>
    Resized: string;
    /// <summary>Name, Pfad, alt, neu: '%s.%s: %s → %s'.</summary>
    Changed: string;
    /// <summary>Name, Anzahl: '%s: %d Eigenschaften geändert'.</summary>
    ChangedMany: string;
    Inserted: string;
    Deleted: string;
    /// <summary>Alter und neuer Name.</summary>
    Renamed: string;
    /// <summary>Anzahl: '%d Komponenten verschoben'.</summary>
    MovedMany: string;
    /// <summary>Anzahl: '%d Änderungen'.</summary>
    Several: string;
    /// <summary>Anzeige für einen nicht gespeicherten Wert: '(Vorgabe)'.</summary>
    DefaultValue: string;
  end;

  TAtlasFormUndo = class
  public
    /// <summary>Objekte des Formulartexts in Textreihenfolge, das Formular zuerst.</summary>
    class function Parse(const AText: string): TArray<TAtlasUndoObject>; static;
    /// <summary>Schritte von ACurrent nach ATarget.</summary>
    class function Plan(const ACurrent, ATarget: string): TAtlasUndoPlan; static;
    /// <summary>Lesbarer Text der Änderung von AOld nach ANew; '' ohne Änderung.</summary>
    class function Describe(const AOld, ANew: string; const AWords: TAtlasUndoWords): string; static;
    /// <summary>Wert für Anzeigen: höchstens eine Zeile und 40 Zeichen; ADefault für ''.</summary>
    class function Shown(const AValue, ADefault: string): string; static;
  end;

  TAtlasUndoState = record
    Text: string;
    /// <summary>Lesbarer Text der Änderung, die zu diesem Stand führte; '' beim Ausgangsstand.</summary>
    Caption: string;
  end;

  /// <summary>Stände eines Formulars; Index zeigt auf den aktuellen.</summary>
  TAtlasFormUndoHistory = class
  public const
    cMinSteps = 5;
    cMaxSteps = 200;
  private
    FStates: TArray<TAtlasUndoState>;
    FIndex: Integer;
    FMaxSteps: Integer;
    procedure Shrink;
    procedure SetMaxSteps(AValue: Integer);
  public
    constructor Create(AMaxSteps: Integer);
    /// <summary>Neuen Stand anhängen (der erste ist der Ausgangsstand); Schritte nach dem aktuellen fallen weg.
    /// False, wenn sich der Text nicht vom aktuellen unterscheidet.</summary>
    function Add(const AText, ACaption: string): Boolean;
    function CanUndo: Boolean;
    function CanRedo: Boolean;
    function Count: Integer;
    function State(AIndex: Integer): TAtlasUndoState;
    /// <summary>Nach dem Zurückladen: AIndex ist aktuell; weicht AActualText ab (nicht alles herstellbar),
    /// gilt er als Text dieses Stands.</summary>
    procedure MoveTo(AIndex: Integer; const AActualText: string);
    procedure Clear;
    property Index: Integer read FIndex;
    /// <summary>Höchstzahl der Schritte ohne den Ausgangsstand (cMinSteps bis cMaxSteps).</summary>
    property MaxSteps: Integer read FMaxSteps write SetMaxSteps;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Math,
  System.Generics.Collections;

const
  cIndent = '  ';
  cShownLength = 40;
  cEventPrefix = 'On';
  cSeparator = ' = ';

function IsIdentifier(const AText: string): Boolean;
var
  mIndex: Integer;
begin
  Result := AText <> '';
  for mIndex := 1 to Length(AText) do
  begin
    if not (CharInSet(AText[mIndex], ['A'..'Z', 'a'..'z', '_']) or
      ((mIndex > 1) and CharInSet(AText[mIndex], ['0'..'9']))) then
    begin
      Exit(False);
    end;
  end;
end;

function IsEvent(const APath, AValue: string): Boolean;
begin
  Result := (Length(APath) > Length(cEventPrefix)) and APath.StartsWith(cEventPrefix) and
    CharInSet(APath[Length(cEventPrefix) + 1], ['A'..'Z']) and
    IsIdentifier(APath) and IsIdentifier(AValue);
end;

/// <summary>Änderung der Klammertiefe durch ALine: ( &lt; { öffnen, ) &gt; } schließen, nicht in Strings.</summary>
function BracketDelta(const ALine: string): Integer;
var
  mIndex: Integer;
  mQuoted: Boolean;
begin
  Result := 0;
  mQuoted := False;
  for mIndex := 1 to Length(ALine) do
  begin
    if ALine[mIndex] = '''' then
    begin
      mQuoted := not mQuoted;
    end
    else if not mQuoted and CharInSet(ALine[mIndex], ['(', '<', '{']) then
    begin
      Inc(Result);
    end
    else if not mQuoted and CharInSet(ALine[mIndex], [')', '>', '}']) then
    begin
      Dec(Result);
    end;
  end;
end;

function Indent(const ALine: string): Integer;
begin
  Result := 0;
  while (Result < Length(ALine)) and (ALine[Result + 1] = ' ') do
  begin
    Inc(Result);
  end;
end;

/// <summary>„object Name: TTyp“ (auch inherited, inline, mit [n] dahinter); False sonst.</summary>
function ObjectLine(const ALine: string; out AKind, AName, ATypeName: string): Boolean;
var
  mRest: string;
  mSpace, mColon, mBracket: Integer;
begin
  AName := '';
  ATypeName := '';
  mSpace := Pos(' ', ALine);
  AKind := LowerCase(Copy(ALine, 1, mSpace - 1));
  if (mSpace = 0) or ((AKind <> 'object') and (AKind <> 'inherited') and (AKind <> 'inline')) then
  begin
    Exit(False);
  end;
  mRest := Copy(ALine, mSpace + 1, MaxInt);
  mBracket := Pos('[', mRest);
  if mBracket > 0 then
  begin
    mRest := Copy(mRest, 1, mBracket - 1);
  end;
  mColon := Pos(':', mRest);
  if mColon > 0 then
  begin
    AName := Trim(Copy(mRest, 1, mColon - 1));
    ATypeName := Trim(Copy(mRest, mColon + 1, MaxInt));
  end
  else
  begin
    ATypeName := Trim(mRest);
  end;
  Result := IsIdentifier(ATypeName) and ((AName = '') or IsIdentifier(AName));
end;

type
  /// <summary>Zustand von Parse.</summary>
  TUndoReader = record
    Lines: TArray<string>;
    Position: Integer;
    Objects: TArray<TAtlasUndoObject>;
    /// <summary>Offene Objekte (Index in Objects) und der Besitzer-Präfix ihrer Kinder.</summary>
    Stack: TArray<Integer>;
    Owners: TArray<string>;
    procedure Open(const AKind, AName, ATypeName: string);
    procedure Close;
    procedure ReadValue(const ALine: string);
    procedure Run(const AText: string);
  end;

procedure TUndoReader.Open(const AKind, AName, ATypeName: string);
var
  mObject: TAtlasUndoObject;
  mOwner: string;
begin
  mObject := Default(TAtlasUndoObject);
  mObject.Name := AName;
  mObject.TypeName := ATypeName;
  mObject.Kind := AKind;
  mOwner := '';
  if Length(Stack) > 0 then
  begin
    mOwner := Owners[High(Owners)];
    mObject.ParentKey := Objects[Stack[High(Stack)]].Key;
    mObject.Key := mOwner + AName;
    // Die Kinder eines eingebetteten Frames gehören dem Frame.
    if AKind = 'inline' then
    begin
      mOwner := mObject.Key + '.';
    end;
  end;
  Objects := Objects + [mObject];
  Stack := Stack + [High(Objects)];
  Owners := Owners + [mOwner];
end;

procedure TUndoReader.Close;
begin
  if Length(Stack) > 0 then
  begin
    SetLength(Stack, Length(Stack) - 1);
    SetLength(Owners, Length(Owners) - 1);
  end;
end;

procedure TUndoReader.ReadValue(const ALine: string);
var
  mValue: TAtlasUndoValue;
  mTrimmed, mNext: string;
  mSeparator, mBase, mOpen: Integer;
  mMore: Boolean;
begin
  mTrimmed := Trim(ALine) + ' ';
  mSeparator := Pos(cSeparator, mTrimmed);
  if (mSeparator = 0) or (Length(Stack) = 0) then
  begin
    Exit;
  end;
  mBase := Indent(ALine);
  mValue := Default(TAtlasUndoValue);
  mValue.Path := Trim(Copy(mTrimmed, 1, mSeparator - 1));
  mValue.Value := Trim(Copy(mTrimmed, mSeparator + Length(cSeparator), MaxInt));
  mValue.Lines := [TrimRight(mTrimmed)];
  mOpen := BracketDelta(mValue.Value);
  // Fortsetzung: Wert erst in der nächsten Zeile, mit + verketteter String oder offene Klammer ( < {.
  mMore := (mValue.Value = '') or mValue.Value.EndsWith('+') or (mOpen > 0);
  while mMore and (Position < High(Lines)) do
  begin
    Inc(Position);
    mNext := Trim(Lines[Position]);
    mValue.Lines := mValue.Lines + [Copy(TrimRight(Lines[Position]), Min(mBase, Indent(Lines[Position])) + 1, MaxInt)];
    if mValue.Value = '' then
    begin
      mValue.Value := mNext;
    end
    else
    begin
      mValue.Value := mValue.Value + #10 + mNext;
    end;
    mOpen := mOpen + BracketDelta(mNext);
    mMore := (mOpen > 0) or mNext.EndsWith('+');
  end;
  mValue.IsEvent := (Length(mValue.Lines) = 1) and IsEvent(mValue.Path, mValue.Value);
  Objects[Stack[High(Stack)]].Values := Objects[Stack[High(Stack)]].Values + [mValue];
end;

procedure TUndoReader.Run(const AText: string);
var
  mLine, mKind, mName, mTypeName: string;
begin
  Lines := AText.Replace(#13#10, #10).Replace(#13, #10).Split([#10]);
  Position := 0;
  while Position <= High(Lines) do
  begin
    mLine := Trim(Lines[Position]);
    if SameText(mLine, 'end') then
    begin
      Close;
    end
    else if ObjectLine(mLine, mKind, mName, mTypeName) then
    begin
      Open(mKind, mName, mTypeName);
    end
    else if mLine <> '' then
    begin
      ReadValue(Lines[Position]);
    end;
    Inc(Position);
  end;
end;

{ TAtlasUndoObject }

function TAtlasUndoObject.IndexOf(const APath: string): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(Values) do
  begin
    if SameText(Values[mIndex].Path, APath) then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

function TAtlasUndoObject.ValueOf(const APath: string): string;
var
  mIndex: Integer;
begin
  Result := '';
  mIndex := IndexOf(APath);
  if mIndex >= 0 then
  begin
    Result := Values[mIndex].Value;
  end;
end;

function TAtlasUndoObject.Plain: Boolean;
begin
  Result := (Kind = 'object') and (Pos('.', Key) = 0) and (Key <> '');
end;

{ TAtlasUndoPlan }

function TAtlasUndoPlan.IsEmpty: Boolean;
begin
  Result := not Structural and (Length(Changes) = 0);
end;

function TAtlasUndoPlan.Structural: Boolean;
begin
  Result := (Length(Deletes) > 0) or (Length(Renames) > 0) or (Length(Creates) > 0);
end;

type
  /// <summary>Zustand von Plan: beide Stände, Zuordnung und was wegfällt bzw. neu ist.</summary>
  TUndoPlanner = record
    Current: TArray<TAtlasUndoObject>;
    Target: TArray<TAtlasUndoObject>;
    /// <summary>Großgeschriebener Schlüssel → Index im jeweiligen Stand.</summary>
    CurrentIndex: TDictionary<string, Integer>;
    TargetIndex: TDictionary<string, Integer>;
    /// <summary>Je Objekt des aktuellen Stands: Index im Zielstand oder -1.</summary>
    Match: TArray<Integer>;
    /// <summary>Je Objekt des Zielstands: Index im aktuellen Stand oder -1.</summary>
    Back: TArray<Integer>;
    Gone: TArray<Boolean>;
    Fresh: TArray<Boolean>;
    Steps: TAtlasUndoPlan;
    procedure Init(const ACurrent, ATarget: string);
    procedure Done;
    procedure MatchRenames;
    function UniqueRename(AOld: Integer): Integer;
    procedure MarkGone;
    procedure MarkFresh;
    procedure AddDeletes;
    procedure AddCreates;
    procedure AddChanges;
    function SameValues(const A, B: TAtlasUndoObject): Boolean;
    function MappedParent(ACurrent: Integer): string;
  end;

function Lookup(AMap: TDictionary<string, Integer>; const AKey: string): Integer;
begin
  if not AMap.TryGetValue(UpperCase(AKey), Result) then
  begin
    Result := -1;
  end;
end;

procedure TUndoPlanner.Init(const ACurrent, ATarget: string);
var
  mIndex: Integer;
begin
  Steps := Default(TAtlasUndoPlan);
  Current := TAtlasFormUndo.Parse(ACurrent);
  Target := TAtlasFormUndo.Parse(ATarget);
  CurrentIndex := TDictionary<string, Integer>.Create;
  TargetIndex := TDictionary<string, Integer>.Create;
  SetLength(Match, Length(Current));
  SetLength(Gone, Length(Current));
  SetLength(Back, Length(Target));
  SetLength(Fresh, Length(Target));
  for mIndex := 0 to High(Current) do
  begin
    CurrentIndex.AddOrSetValue(UpperCase(Current[mIndex].Key), mIndex);
  end;
  for mIndex := 0 to High(Target) do
  begin
    TargetIndex.AddOrSetValue(UpperCase(Target[mIndex].Key), mIndex);
    Back[mIndex] := Lookup(CurrentIndex, Target[mIndex].Key);
  end;
  for mIndex := 0 to High(Current) do
  begin
    Match[mIndex] := Lookup(TargetIndex, Current[mIndex].Key);
  end;
end;

procedure TUndoPlanner.Done;
begin
  CurrentIndex.Free;
  TargetIndex.Free;
end;

function TUndoPlanner.SameValues(const A, B: TAtlasUndoObject): Boolean;
var
  mIndex: Integer;
begin
  Result := (A.TypeName = B.TypeName) and (Length(A.Values) = Length(B.Values));
  for mIndex := 0 to High(A.Values) do
  begin
    Result := Result and SameText(A.Values[mIndex].Path, B.Values[mIndex].Path) and
      (A.Values[mIndex].Value = B.Values[mIndex].Value);
  end;
end;

procedure TUndoPlanner.MatchRenames;
var
  mOld, mFound: Integer;
  mRename: TAtlasUndoRename;
begin
  // Umbenannt: genau ein verschwundenes und ein neues Objekt mit gleicher Klasse, gleichem Elternelement
  // und gleichen Werten.
  for mOld := 0 to High(Current) do
  begin
    if (Match[mOld] >= 0) or not Current[mOld].Plain then
    begin
      Continue;
    end;
    mFound := UniqueRename(mOld);
    if mFound >= 0 then
    begin
      Match[mOld] := mFound;
      Back[mFound] := mOld;
      mRename.OldKey := Current[mOld].Key;
      mRename.NewName := Target[mFound].Name;
      Steps.Renames := Steps.Renames + [mRename];
    end;
  end;
end;

function TUndoPlanner.UniqueRename(AOld: Integer): Integer;
var
  mNew: Integer;
begin
  // Index des einzigen passenden neuen Objekts; -1, wenn keins oder mehrere passen.
  Result := -1;
  for mNew := 0 to High(Target) do
  begin
    if (Back[mNew] < 0) and Target[mNew].Plain and SameText(Target[mNew].ParentKey, MappedParent(AOld)) and
      SameValues(Current[AOld], Target[mNew]) then
    begin
      if Result >= 0 then
      begin
        Result := -1;
        Exit;
      end;
      Result := mNew;
    end;
  end;
end;

function TUndoPlanner.MappedParent(ACurrent: Integer): string;
var
  mParent: Integer;
begin
  Result := Current[ACurrent].ParentKey;
  mParent := Lookup(CurrentIndex, Result);
  if (mParent >= 0) and (Match[mParent] >= 0) then
  begin
    Result := Target[Match[mParent]].Key;
  end;
end;

procedure TUndoPlanner.MarkGone;
var
  mIndex, mParent: Integer;
begin
  // Objekte stehen in Textreihenfolge, Eltern also vor Kindern.
  for mIndex := 1 to High(Current) do
  begin
    mParent := Lookup(CurrentIndex, Current[mIndex].ParentKey);
    Gone[mIndex] := (Match[mIndex] < 0) or ((mParent >= 0) and Gone[mParent]) or
      not SameText(MappedParent(mIndex), Target[Match[mIndex]].ParentKey);
  end;
end;

procedure TUndoPlanner.MarkFresh;
var
  mIndex, mParent: Integer;
begin
  for mIndex := 1 to High(Target) do
  begin
    mParent := Lookup(TargetIndex, Target[mIndex].ParentKey);
    Fresh[mIndex] := (Back[mIndex] < 0) or Gone[Back[mIndex]] or ((mParent >= 0) and Fresh[mParent]);
  end;
end;

procedure TUndoPlanner.AddDeletes;
var
  mIndex, mParent: Integer;
begin
  for mIndex := 1 to High(Current) do
  begin
    mParent := Lookup(CurrentIndex, Current[mIndex].ParentKey);
    if not Gone[mIndex] or ((mParent >= 0) and Gone[mParent]) then
    begin
      Continue;
    end;
    if Current[mIndex].Plain then
    begin
      Steps.Deletes := Steps.Deletes + [Current[mIndex].Key];
    end
    else
    begin
      Steps.Skipped := Steps.Skipped + [Current[mIndex].Key];
    end;
  end;
end;

/// <summary>Kleiner Formulartext mit den Werten AIndexes von AObject (ohne Ereignisse).</summary>
function ObjectText(const AObject: TAtlasUndoObject; const AIndexes: TArray<Integer>): string;
var
  mIndex: Integer;
  mLine: string;
begin
  Result := '';
  if Length(AIndexes) = 0 then
  begin
    Exit;
  end;
  Result := 'object ' + AObject.Name + ': ' + AObject.TypeName + sLineBreak;
  for mIndex in AIndexes do
  begin
    for mLine in AObject.Values[mIndex].Lines do
    begin
      Result := Result + cIndent + mLine + sLineBreak;
    end;
  end;
  Result := Result + 'end';
end;

function Event(const APath, AHandler: string): TAtlasUndoEvent;
begin
  Result.Path := APath;
  Result.Handler := AHandler;
end;

/// <summary>Anlegen: alle Werte von AObject.</summary>
function CreateOf(const AObject: TAtlasUndoObject): TAtlasUndoComponent;
var
  mIndex: Integer;
  mIndexes: TArray<Integer>;
begin
  Result := Default(TAtlasUndoComponent);
  Result.Key := AObject.Key;
  Result.Name := AObject.Name;
  Result.TypeName := AObject.TypeName;
  Result.ParentKey := AObject.ParentKey;
  mIndexes := nil;
  for mIndex := 0 to High(AObject.Values) do
  begin
    if AObject.Values[mIndex].IsEvent then
    begin
      Result.Events := Result.Events + [Event(AObject.Values[mIndex].Path, AObject.Values[mIndex].Value)];
    end
    else
    begin
      mIndexes := mIndexes + [mIndex];
      Result.Paths := Result.Paths + [AObject.Values[mIndex].Path];
    end;
  end;
  Result.Text := ObjectText(AObject, mIndexes);
end;

procedure TUndoPlanner.AddCreates;
var
  mIndex, mParent: Integer;
  mSkipped: TArray<Boolean>;
begin
  SetLength(mSkipped, Length(Target));
  for mIndex := 1 to High(Target) do
  begin
    if not Fresh[mIndex] then
    begin
      Continue;
    end;
    mParent := Lookup(TargetIndex, Target[mIndex].ParentKey);
    if (mParent >= 0) and mSkipped[mParent] then
    begin
      mSkipped[mIndex] := True;
    end
    else if Target[mIndex].Plain then
    begin
      Steps.Creates := Steps.Creates + [CreateOf(Target[mIndex])];
    end
    else
    begin
      mSkipped[mIndex] := True;
      Steps.Skipped := Steps.Skipped + [Target[mIndex].Key];
    end;
  end;
end;

/// <summary>Unterschiede von AOld nach ANew; False ohne.</summary>
function ChangeOf(const AOld, ANew: TAtlasUndoObject; out AChange: TAtlasUndoComponent): Boolean;
var
  mIndex, mOld: Integer;
  mIndexes: TArray<Integer>;
begin
  AChange := Default(TAtlasUndoComponent);
  AChange.Key := ANew.Key;
  AChange.Name := ANew.Name;
  AChange.TypeName := ANew.TypeName;
  AChange.ParentKey := ANew.ParentKey;
  mIndexes := nil;
  for mIndex := 0 to High(ANew.Values) do
  begin
    mOld := AOld.IndexOf(ANew.Values[mIndex].Path);
    if (mOld >= 0) and (AOld.Values[mOld].Value = ANew.Values[mIndex].Value) then
    begin
      Continue;
    end;
    if ANew.Values[mIndex].IsEvent then
    begin
      AChange.Events := AChange.Events + [Event(ANew.Values[mIndex].Path, ANew.Values[mIndex].Value)];
    end
    else
    begin
      mIndexes := mIndexes + [mIndex];
      AChange.Paths := AChange.Paths + [ANew.Values[mIndex].Path];
    end;
  end;
  for mOld := 0 to High(AOld.Values) do
  begin
    if ANew.IndexOf(AOld.Values[mOld].Path) >= 0 then
    begin
      Continue;
    end;
    if AOld.Values[mOld].IsEvent then
    begin
      AChange.Events := AChange.Events + [Event(AOld.Values[mOld].Path, '')];
    end
    else
    begin
      AChange.Resets := AChange.Resets + [AOld.Values[mOld].Path];
    end;
  end;
  AChange.Text := ObjectText(ANew, mIndexes);
  Result := (Length(AChange.Paths) > 0) or (Length(AChange.Resets) > 0) or (Length(AChange.Events) > 0);
end;

procedure TUndoPlanner.AddChanges;
var
  mIndex: Integer;
  mChange: TAtlasUndoComponent;
begin
  for mIndex := 0 to High(Target) do
  begin
    if not Fresh[mIndex] and (Back[mIndex] >= 0) and
      ChangeOf(Current[Back[mIndex]], Target[mIndex], mChange) then
    begin
      Steps.Changes := Steps.Changes + [mChange];
    end;
  end;
end;

{ TAtlasFormUndo }

class function TAtlasFormUndo.Parse(const AText: string): TArray<TAtlasUndoObject>;
var
  mReader: TUndoReader;
begin
  mReader := Default(TUndoReader);
  mReader.Run(AText);
  Result := mReader.Objects;
end;

class function TAtlasFormUndo.Plan(const ACurrent, ATarget: string): TAtlasUndoPlan;
var
  mPlanner: TUndoPlanner;
begin
  mPlanner := Default(TUndoPlanner);
  mPlanner.Init(ACurrent, ATarget);
  try
    // Ohne Formular in einem der Stände (leerer oder kaputter Text) gibt es nichts zu tun.
    if (Length(mPlanner.Current) > 0) and (Length(mPlanner.Target) > 0) then
    begin
      mPlanner.MatchRenames;
      mPlanner.MarkGone;
      mPlanner.MarkFresh;
      mPlanner.AddDeletes;
      mPlanner.AddCreates;
      mPlanner.AddChanges;
    end;
    Result := mPlanner.Steps;
  finally
    mPlanner.Done;
  end;
end;

class function TAtlasFormUndo.Shown(const AValue, ADefault: string): string;
var
  mBreak: Integer;
begin
  if AValue = '' then
  begin
    Exit(ADefault);
  end;
  Result := AValue;
  mBreak := Pos(#10, Result);
  if mBreak > 0 then
  begin
    Result := Copy(Result, 1, mBreak - 1) + ' …';
  end;
  if Length(Result) > cShownLength then
  begin
    Result := Copy(Result, 1, cShownLength - 1) + '…';
  end;
end;

/// <summary>Pfade, die etwas bedeuten: ohne die Hilfswerte Explicit… und DesignSize.</summary>
function Meaningful(const AChange: TAtlasUndoComponent): TArray<string>;
var
  mPath: string;
  mEvent: TAtlasUndoEvent;
begin
  Result := nil;
  for mPath in AChange.Paths + AChange.Resets do
  begin
    if not mPath.StartsWith('Explicit', True) and not SameText(mPath, 'DesignSize') then
    begin
      Result := Result + [mPath];
    end;
  end;
  for mEvent in AChange.Events do
  begin
    Result := Result + [mEvent.Path];
  end;
end;

/// <summary>Alle APaths aus AAllowed?</summary>
function Within(const APaths, AAllowed: array of string): Boolean;
var
  mPath: string;
begin
  Result := Length(APaths) > 0;
  for mPath in APaths do
  begin
    Result := Result and MatchText(mPath, AAllowed);
  end;
end;

function IsMove(const AChange: TAtlasUndoComponent): Boolean;
begin
  Result := Within(Meaningful(AChange), ['Left', 'Top']);
end;

function Number(const AObject: TAtlasUndoObject; const APath: string): string;
begin
  Result := AObject.ValueOf(APath);
  if Result = '' then
  begin
    Result := '0';
  end;
end;

/// <summary>Text einer Änderung an einer Komponente (AOld, ANew: das Objekt vorher und nachher).</summary>
function ChangeText(const AOld, ANew: TAtlasUndoObject; const AChange: TAtlasUndoComponent;
  const AWords: TAtlasUndoWords): string;
var
  mPaths: TArray<string>;
begin
  mPaths := Meaningful(AChange);
  if IsMove(AChange) then
  begin
    Result := Format(AWords.Moved, [ANew.Name, Number(AOld, 'Left'), Number(AOld, 'Top'), Number(ANew, 'Left'),
      Number(ANew, 'Top')]);
  end
  else if Within(mPaths, ['Left', 'Top', 'Width', 'Height']) then
  begin
    Result := Format(AWords.Resized, [ANew.Name, Number(AOld, 'Width'), Number(AOld, 'Height'),
      Number(ANew, 'Width'), Number(ANew, 'Height')]);
  end
  else if Length(mPaths) = 1 then
  begin
    Result := Format(AWords.Changed, [ANew.Name, mPaths[0], TAtlasFormUndo.Shown(AOld.ValueOf(mPaths[0]),
      AWords.DefaultValue), TAtlasFormUndo.Shown(ANew.ValueOf(mPaths[0]), AWords.DefaultValue)]);
  end
  else
  begin
    Result := Format(AWords.ChangedMany, [ANew.Name, Length(mPaths)]);
  end;
end;

/// <summary>Angelegte Komponenten ohne ihre Kinder.</summary>
function TopCreates(const APlan: TAtlasUndoPlan): TArray<TAtlasUndoComponent>;
var
  mCreate, mOther: TAtlasUndoComponent;
  mInner: Boolean;
begin
  Result := nil;
  for mCreate in APlan.Creates do
  begin
    mInner := False;
    for mOther in APlan.Creates do
    begin
      mInner := mInner or SameText(mOther.Key, mCreate.ParentKey);
    end;
    if not mInner then
    begin
      Result := Result + [mCreate];
    end;
  end;
end;

function ObjectOf(const AObjects: TArray<TAtlasUndoObject>; const AKey: string): TAtlasUndoObject;
var
  mObject: TAtlasUndoObject;
begin
  for mObject in AObjects do
  begin
    if SameText(mObject.Key, AKey) then
    begin
      Exit(mObject);
    end;
  end;
  Result := Default(TAtlasUndoObject);
end;

function AllMoves(const APlan: TAtlasUndoPlan): Boolean;
var
  mChange: TAtlasUndoComponent;
begin
  Result := not APlan.Structural and (Length(APlan.Changes) > 0);
  for mChange in APlan.Changes do
  begin
    Result := Result and IsMove(mChange);
  end;
end;

class function TAtlasFormUndo.Describe(const AOld, ANew: string; const AWords: TAtlasUndoWords): string;
var
  mPlan: TAtlasUndoPlan;
  mCreates: TArray<TAtlasUndoComponent>;
  mCount: Integer;
  mOld, mNew: TArray<TAtlasUndoObject>;
begin
  mPlan := Plan(AOld, ANew);
  mCreates := TopCreates(mPlan);
  mCount := Length(mPlan.Deletes) + Length(mPlan.Renames) + Length(mCreates) + Length(mPlan.Changes);
  Result := '';
  if mCount = 0 then
  begin
    Exit;
  end;
  if mCount > 1 then
  begin
    if AllMoves(mPlan) then
    begin
      Exit(Format(AWords.MovedMany, [mCount]));
    end;
    Exit(Format(AWords.Several, [mCount]));
  end;
  if Length(mPlan.Deletes) = 1 then
  begin
    Result := Format(AWords.Deleted, [mPlan.Deletes[0]]);
  end
  else if Length(mPlan.Renames) = 1 then
  begin
    Result := Format(AWords.Renamed, [mPlan.Renames[0].OldKey, mPlan.Renames[0].NewName]);
  end
  else if Length(mCreates) = 1 then
  begin
    Result := Format(AWords.Inserted, [mCreates[0].Name]);
  end
  else
  begin
    mOld := Parse(AOld);
    mNew := Parse(ANew);
    Result := ChangeText(ObjectOf(mOld, mPlan.Changes[0].Key), ObjectOf(mNew, mPlan.Changes[0].Key),
      mPlan.Changes[0], AWords);
  end;
end;

{ TAtlasFormUndoHistory }

constructor TAtlasFormUndoHistory.Create(AMaxSteps: Integer);
begin
  inherited Create;
  FIndex := -1;
  SetMaxSteps(AMaxSteps);
end;

procedure TAtlasFormUndoHistory.SetMaxSteps(AValue: Integer);
begin
  FMaxSteps := EnsureRange(AValue, cMinSteps, cMaxSteps);
  Shrink;
end;

procedure TAtlasFormUndoHistory.Shrink;
var
  mDrop: Integer;
begin
  // Ausgangsstand plus FMaxSteps Schritte; die ältesten fallen weg.
  mDrop := Length(FStates) - FMaxSteps - 1;
  if mDrop > 0 then
  begin
    Delete(FStates, 0, mDrop);
    FIndex := Max(0, FIndex - mDrop);
    FStates[0].Caption := '';
  end;
end;

function TAtlasFormUndoHistory.Add(const AText, ACaption: string): Boolean;
var
  mState: TAtlasUndoState;
begin
  Result := (FIndex < 0) or (FStates[FIndex].Text <> AText);
  if not Result then
  begin
    Exit;
  end;
  SetLength(FStates, FIndex + 1);
  mState.Text := AText;
  mState.Caption := '';
  if FIndex >= 0 then
  begin
    mState.Caption := ACaption;
  end;
  FStates := FStates + [mState];
  FIndex := High(FStates);
  Shrink;
end;

function TAtlasFormUndoHistory.CanUndo: Boolean;
begin
  Result := FIndex > 0;
end;

function TAtlasFormUndoHistory.CanRedo: Boolean;
begin
  Result := (FIndex >= 0) and (FIndex < High(FStates));
end;

function TAtlasFormUndoHistory.Count: Integer;
begin
  Result := Length(FStates);
end;

function TAtlasFormUndoHistory.State(AIndex: Integer): TAtlasUndoState;
begin
  Result := FStates[AIndex];
end;

procedure TAtlasFormUndoHistory.MoveTo(AIndex: Integer; const AActualText: string);
begin
  if (AIndex < 0) or (AIndex > High(FStates)) then
  begin
    Exit;
  end;
  FIndex := AIndex;
  if (AActualText <> '') and (AActualText <> FStates[AIndex].Text) then
  begin
    FStates[AIndex].Text := AActualText;
  end;
end;

procedure TAtlasFormUndoHistory.Clear;
begin
  FStates := nil;
  FIndex := -1;
end;

end.
