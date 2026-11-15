unit Atlas.Core.Designer.Groups;

// Gruppen ohne Container im Designer (#744), ohne VCL und Windows.
// - Je Formular (Schlüssel vom Aufrufer) benannte Gruppen mit mindestens
//   zwei Mitgliedern; ein Mitglied gehört höchstens zu einer Gruppe, keine
//   Verschachtelung. Wer neu gruppiert wird, verlässt seine alte Gruppe.
// - Auswahl erweitern: jede berührte Gruppe kommt ganz dazu.
// - Umbenannte Mitglieder ziehen mit; gelöschte fallen heraus, eine Gruppe
//   mit weniger als zwei Mitgliedern löst sich auf.
// - Kopie erkennen: gleich viele neue Komponenten mit denselben Klassen und
//   derselben Lage zueinander wie eine Gruppe werden eine neue Gruppe.
// - Ablage und Namensvorschlag wie die Auswahlsätze (#739,
//   TAtlasSelectionSets); die DFM bleibt unberührt.
// - TAtlasGroupRules: Ablagedatei und Schlüssel des Formulars, zweiter Klick
//   auf ein Mitglied, Rahmen um die Mitglieder.

interface

uses
  System.Types,
  Atlas.Core.Designer.SelectionSets;

type
  /// <summary>Lage und Klasse einer Komponente für die Kopie-Erkennung.</summary>
  TAtlasGroupShape = record
    Name: string;
    ClassName: string;
    Bounds: TRect;
    class function Create(const AName, AClassName: string; const ABounds: TRect): TAtlasGroupShape; static;
  end;

  TAtlasDesignerGroups = class
  public const
    cMinMembers = 2;
  private
    FSets: TAtlasSelectionSets;
    function GetChanged: Boolean;
    procedure SetChanged(AValue: Boolean);
    procedure Prune(const AForm: string);
    function UniqueName(const AForm, AName: string): string;
  public
    constructor Create;
    destructor Destroy; override;
    function GroupsOf(const AForm: string): TArray<TAtlasSelectionSet>;
    /// <summary>Neue Gruppe aus AMembers (mindestens zwei); Ergebnis: Index oder -1.</summary>
    function Add(const AForm, AName: string; const AMembers: TArray<string>): Integer;
    /// <summary>Gruppe von AMember auflösen; False, wenn AMember in keiner ist.</summary>
    function Ungroup(const AForm, AMember: string): Boolean;
    /// <summary>Index der Gruppe von AMember oder -1.</summary>
    function IndexOf(const AForm, AMember: string): Integer;
    /// <summary>ASelection plus alle Mitglieder der berührten Gruppen, ohne Doppelte.</summary>
    function Expand(const AForm: string; const ASelection: TArray<string>): TArray<string>;
    procedure ComponentRenamed(const AForm, AOldName, ANewName: string);
    procedure ComponentDeleted(const AForm, AName: string);
    /// <summary>Alle Gruppen des Formulars ersetzen (Rückgängig).</summary>
    procedure Restore(const AForm: string; const AGroups: TArray<TAtlasSelectionSet>);
    /// <summary>Ist ANew eine Kopie einer Gruppe? Dann neue Gruppe; Ergebnis: Index oder -1.</summary>
    function AddCopy(const AForm: string; const AGroupShapes: TArray<TArray<TAtlasGroupShape>>;
      const ANew: TArray<TAtlasGroupShape>): Integer;
    function ToJson: string;
    function LoadJson(const AText: string): Boolean;
    property Changed: Boolean read GetChanged write SetChanged;
    /// <summary>Alle Parents gleich (mindestens ein Eintrag)?</summary>
    class function SameParent(const AParents: TArray<string>): Boolean; static;
    /// <summary>Text des ersten Labels ohne &amp; und Doppelpunkt, sonst gemeinsamer Wortteil der Namen.</summary>
    class function SuggestName(const AMembers: TArray<string>; const AFirstLabel: string): string; static;
    /// <summary>Gleiche Klassen und gleiche Lage zueinander (nach Lage geordnet)?</summary>
    class function IsCopy(const AGroup, ANew: TArray<TAtlasGroupShape>): Boolean; static;
  end;

  /// <summary>Ablage, Klicks und Rahmen der Gruppen.</summary>
  TAtlasGroupRules = class
  public const
    cLocalFile = 'designer-groups.json';
    cSharedFile = '.atlas-groups.json';
  public
    /// <summary>Schlüssel des Formulars in der Ablage: geteilt nur der Dateiname (die Datei liegt daneben),
    /// lokal der ganze Pfad.</summary>
    class function FormKey(const AFormFile: string; AShared: Boolean): string; static;
    /// <summary>Datei der Ablage: geteilt neben dem Formular, lokal in ALocalData\Atlas (leer: ATemp\Atlas).
    /// </summary>
    class function StorePath(const AFormFile: string; AShared: Boolean; const ALocalData, ATemp: string): string;
      static;
    /// <summary>Gehört ein Name aus ASelected zu AMembers (ohne Groß-/Kleinschreibung)?</summary>
    class function Touches(const AMembers, ASelected: TArray<string>): Boolean; static;
    /// <summary>designer.groups.memberClick = doubleClick: Wird das zuletzt zur Gruppe ergänzte Mitglied ASingle
    /// innerhalb der Doppelklickzeit noch einmal allein angeklickt, wählt der Klick es allein.</summary>
    class function SecondClick(ADoubleClickMode: Boolean; const ANames: TArray<string>; const ASingle: string;
      AElapsedMs, ADoubleClickMs: UInt64): Boolean; static;
    /// <summary>Rahmen um die Mitglieder: Vereinigung der nicht leeren Lagen, um AGap größer; leer ohne.</summary>
    class function Frame(const ABounds: TArray<TRect>; AGap: Integer): TRect; static;
    /// <summary>Index der Lage oben links (oberste, bei Gleichstand linke); -1 ohne.</summary>
    class function TopLeft(const ABounds: TArray<TRect>): Integer; static;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  System.Math;

{ TAtlasGroupShape }

class function TAtlasGroupShape.Create(const AName, AClassName: string; const ABounds: TRect): TAtlasGroupShape;
begin
  Result.Name := AName;
  Result.ClassName := AClassName;
  Result.Bounds := ABounds;
end;

function Contains(const ANames: TArray<string>; const AName: string): Boolean;
var
  mName: string;
begin
  for mName in ANames do
  begin
    if SameText(mName, AName) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function Distinct(const ANames: TArray<string>): TArray<string>;
var
  mName: string;
begin
  Result := nil;
  for mName in ANames do
  begin
    if (Trim(mName) <> '') and not Contains(Result, mName) then
    begin
      Result := Result + [mName];
    end;
  end;
end;

/// <summary>Nach Oberkante, dann linker Kante geordnet.</summary>
function Sorted(const AShapes: TArray<TAtlasGroupShape>): TArray<TAtlasGroupShape>;
var
  mOuter, mInner: Integer;
  mSwap: TAtlasGroupShape;

  function Before(const A, B: TAtlasGroupShape): Boolean;
  begin
    Result := (A.Bounds.Top < B.Bounds.Top) or ((A.Bounds.Top = B.Bounds.Top) and (A.Bounds.Left < B.Bounds.Left));
  end;

begin
  Result := Copy(AShapes);
  for mOuter := 1 to High(Result) do
  begin
    mInner := mOuter;
    while (mInner > 0) and Before(Result[mInner], Result[mInner - 1]) do
    begin
      mSwap := Result[mInner];
      Result[mInner] := Result[mInner - 1];
      Result[mInner - 1] := mSwap;
      Dec(mInner);
    end;
  end;
end;

{ TAtlasDesignerGroups }

constructor TAtlasDesignerGroups.Create;
begin
  inherited Create;
  FSets := TAtlasSelectionSets.Create;
end;

destructor TAtlasDesignerGroups.Destroy;
begin
  FSets.Free;
  inherited Destroy;
end;

function TAtlasDesignerGroups.GetChanged: Boolean;
begin
  Result := FSets.Changed;
end;

procedure TAtlasDesignerGroups.SetChanged(AValue: Boolean);
begin
  FSets.Changed := AValue;
end;

procedure TAtlasDesignerGroups.Prune(const AForm: string);
var
  mGroups: TArray<TAtlasSelectionSet>;
  mIndex: Integer;
begin
  mGroups := GroupsOf(AForm);
  for mIndex := High(mGroups) downto 0 do
  begin
    if Length(mGroups[mIndex].Members) < cMinMembers then
    begin
      FSets.Delete(AForm, mIndex);
    end;
  end;
end;

function TAtlasDesignerGroups.UniqueName(const AForm, AName: string): string;
var
  mNumber: Integer;
  mGroup: TAtlasSelectionSet;
  mTaken: Boolean;
begin
  Result := AName;
  mNumber := 1;
  repeat
    mTaken := False;
    for mGroup in GroupsOf(AForm) do
    begin
      mTaken := mTaken or SameText(mGroup.Name, Result);
    end;
    if mTaken then
    begin
      Inc(mNumber);
      Result := AName + ' ' + IntToStr(mNumber);
    end;
  until not mTaken;
end;

function TAtlasDesignerGroups.GroupsOf(const AForm: string): TArray<TAtlasSelectionSet>;
begin
  Result := FSets.SetsOf(AForm);
end;

function TAtlasDesignerGroups.Add(const AForm, AName: string; const AMembers: TArray<string>): Integer;
var
  mMembers, mRest: TArray<string>;
  mGroups: TArray<TAtlasSelectionSet>;
  mIndex: Integer;
  mMember: string;
begin
  mMembers := Distinct(AMembers);
  if Length(mMembers) < cMinMembers then
  begin
    Exit(-1);
  end;
  // Mitglieder verlassen ihre alten Gruppen.
  mGroups := GroupsOf(AForm);
  for mIndex := 0 to High(mGroups) do
  begin
    mRest := nil;
    for mMember in mGroups[mIndex].Members do
    begin
      if not Contains(mMembers, mMember) then
      begin
        mRest := mRest + [mMember];
      end;
    end;
    if Length(mRest) <> Length(mGroups[mIndex].Members) then
    begin
      FSets.Replace(AForm, mIndex, mRest);
    end;
  end;
  Prune(AForm);
  Result := FSets.Add(AForm, UniqueName(AForm, AName), mMembers);
end;

function TAtlasDesignerGroups.Ungroup(const AForm, AMember: string): Boolean;
var
  mIndex: Integer;
begin
  mIndex := IndexOf(AForm, AMember);
  Result := mIndex >= 0;
  if Result then
  begin
    FSets.Delete(AForm, mIndex);
  end;
end;

function TAtlasDesignerGroups.IndexOf(const AForm, AMember: string): Integer;
var
  mGroups: TArray<TAtlasSelectionSet>;
  mIndex: Integer;
begin
  mGroups := GroupsOf(AForm);
  for mIndex := 0 to High(mGroups) do
  begin
    if Contains(mGroups[mIndex].Members, AMember) then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

function TAtlasDesignerGroups.Expand(const AForm: string; const ASelection: TArray<string>): TArray<string>;
var
  mName, mMember: string;
  mIndex: Integer;
  mGroups: TArray<TAtlasSelectionSet>;
begin
  Result := Distinct(ASelection);
  mGroups := GroupsOf(AForm);
  for mName in ASelection do
  begin
    mIndex := IndexOf(AForm, mName);
    if mIndex < 0 then
    begin
      Continue;
    end;
    for mMember in mGroups[mIndex].Members do
    begin
      if not Contains(Result, mMember) then
      begin
        Result := Result + [mMember];
      end;
    end;
  end;
end;

procedure TAtlasDesignerGroups.ComponentRenamed(const AForm, AOldName, ANewName: string);
begin
  FSets.ComponentRenamed(AForm, AOldName, ANewName);
end;

procedure TAtlasDesignerGroups.ComponentDeleted(const AForm, AName: string);
begin
  FSets.ComponentDeleted(AForm, AName);
  Prune(AForm);
end;

procedure TAtlasDesignerGroups.Restore(const AForm: string; const AGroups: TArray<TAtlasSelectionSet>);
var
  mIndex: Integer;
  mGroup: TAtlasSelectionSet;
begin
  for mIndex := High(GroupsOf(AForm)) downto 0 do
  begin
    FSets.Delete(AForm, mIndex);
  end;
  for mGroup in AGroups do
  begin
    FSets.Add(AForm, mGroup.Name, mGroup.Members);
  end;
  FSets.Changed := True;
end;

function TAtlasDesignerGroups.AddCopy(const AForm: string; const AGroupShapes: TArray<TArray<TAtlasGroupShape>>;
  const ANew: TArray<TAtlasGroupShape>): Integer;
var
  mIndex: Integer;
  mNames: TArray<string>;
  mShape: TAtlasGroupShape;
  mGroups: TArray<TAtlasSelectionSet>;
begin
  Result := -1;
  mGroups := GroupsOf(AForm);
  for mIndex := 0 to Min(High(AGroupShapes), High(mGroups)) do
  begin
    if IsCopy(AGroupShapes[mIndex], ANew) then
    begin
      mNames := nil;
      for mShape in ANew do
      begin
        mNames := mNames + [mShape.Name];
      end;
      Exit(Add(AForm, mGroups[mIndex].Name, mNames));
    end;
  end;
end;

function TAtlasDesignerGroups.ToJson: string;
begin
  Result := FSets.ToJson;
end;

function TAtlasDesignerGroups.LoadJson(const AText: string): Boolean;
begin
  Result := FSets.LoadJson(AText);
end;

class function TAtlasDesignerGroups.SameParent(const AParents: TArray<string>): Boolean;
var
  mParent: string;
begin
  Result := Length(AParents) > 0;
  for mParent in AParents do
  begin
    Result := Result and SameText(mParent, AParents[0]);
  end;
end;

class function TAtlasDesignerGroups.SuggestName(const AMembers: TArray<string>; const AFirstLabel: string): string;
begin
  Result := Trim(StringReplace(AFirstLabel, '&', '', [rfReplaceAll]));
  while (Result <> '') and CharInSet(Result[Length(Result)], [':', '.', ' ']) do
  begin
    Result := Copy(Result, 1, Length(Result) - 1);
  end;
  if Result = '' then
  begin
    Result := TAtlasSelectionSets.SuggestName(AMembers);
  end;
end;

class function TAtlasDesignerGroups.IsCopy(const AGroup, ANew: TArray<TAtlasGroupShape>): Boolean;
var
  mGroup, mNew: TArray<TAtlasGroupShape>;
  mIndex: Integer;
  mOffset: TPoint;
begin
  Result := (Length(AGroup) >= cMinMembers) and (Length(AGroup) = Length(ANew));
  if not Result then
  begin
    Exit;
  end;
  mGroup := Sorted(AGroup);
  mNew := Sorted(ANew);
  mOffset := Point(mNew[0].Bounds.Left - mGroup[0].Bounds.Left, mNew[0].Bounds.Top - mGroup[0].Bounds.Top);
  for mIndex := 0 to High(mGroup) do
  begin
    Result := Result and SameText(mGroup[mIndex].ClassName, mNew[mIndex].ClassName) and
      (mNew[mIndex].Bounds.Left - mGroup[mIndex].Bounds.Left = mOffset.X) and
      (mNew[mIndex].Bounds.Top - mGroup[mIndex].Bounds.Top = mOffset.Y) and
      (mNew[mIndex].Bounds.Width = mGroup[mIndex].Bounds.Width) and
      (mNew[mIndex].Bounds.Height = mGroup[mIndex].Bounds.Height);
  end;
end;

{ TAtlasGroupRules }

class function TAtlasGroupRules.FormKey(const AFormFile: string; AShared: Boolean): string;
begin
  Result := AFormFile;
  if AShared then
  begin
    Result := ExtractFileName(AFormFile);
  end;
end;

class function TAtlasGroupRules.StorePath(const AFormFile: string; AShared: Boolean;
  const ALocalData, ATemp: string): string;
var
  mLocal: string;
begin
  if AShared then
  begin
    Exit(TPath.Combine(ExtractFilePath(AFormFile), cSharedFile));
  end;
  mLocal := ALocalData;
  if mLocal = '' then
  begin
    mLocal := ATemp;
  end;
  Result := TPath.Combine(TPath.Combine(mLocal, 'Atlas'), cLocalFile);
end;

class function TAtlasGroupRules.Touches(const AMembers, ASelected: TArray<string>): Boolean;
var
  mName, mMember: string;
begin
  for mName in ASelected do
  begin
    for mMember in AMembers do
    begin
      if SameText(mName, mMember) then
      begin
        Exit(True);
      end;
    end;
  end;
  Result := False;
end;

class function TAtlasGroupRules.SecondClick(ADoubleClickMode: Boolean; const ANames: TArray<string>;
  const ASingle: string; AElapsedMs, ADoubleClickMs: UInt64): Boolean;
begin
  Result := ADoubleClickMode and (Length(ANames) = 1) and SameText(ANames[0], ASingle) and
    (AElapsedMs <= ADoubleClickMs);
end;

class function TAtlasGroupRules.Frame(const ABounds: TArray<TRect>; AGap: Integer): TRect;
var
  mBounds: TRect;
begin
  Result := TRect.Empty;
  for mBounds in ABounds do
  begin
    Result.Union(mBounds);
  end;
  if not Result.IsEmpty then
  begin
    Result.Inflate(AGap, AGap);
  end;
end;

class function TAtlasGroupRules.TopLeft(const ABounds: TArray<TRect>): Integer;
var
  mIndex: Integer;
begin
  Result := -1;
  for mIndex := 0 to High(ABounds) do
  begin
    if (Result < 0) or (ABounds[mIndex].Top < ABounds[Result].Top) or
      ((ABounds[mIndex].Top = ABounds[Result].Top) and (ABounds[mIndex].Left < ABounds[Result].Left)) then
    begin
      Result := mIndex;
    end;
  end;
end;

end.
