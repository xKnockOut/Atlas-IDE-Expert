unit Atlas.Core.Designer.TabOrder;

// Tab-Reihenfolge im Designer (#1442, #603), ohne VCL und Windows:
// - TAtlasTabStop: Steuerelement mit TabOrder (TWinControl), Lage im Client
//   der Wurzel, ob es den Fokus bekommt (TabStop) und ob es Kinder hat.
// - TAtlasTabOrder.Issues: je Steuerelement die Auffälligkeit seiner Marke,
//   je Elternelement: doppelte TabOrder, Lücke in der Folge und Rücksprung
//   gegen die Lesereihenfolge (Zeile, dann links nach rechts bzw. bei
//   rechts-nach-links rechts nach links). Rücksprünge zählen nur zwischen
//   Steuerelementen, die Tab erreicht (TabStop oder Container).
// - Paths: verschachtelte Reihenfolge als Pfad („2.1“ = Kind 1 im
//   Container mit TabOrder 2).
// - ReadingOrder: neue TabOrder je Steuerelement nach der Lesereihenfolge
//   („Nach Lesereihenfolge sortieren“); Assignments: Folge von Zuweisungen,
//   die nacheinander gesetzt genau diesen Stand ergibt (der Setter der VCL
//   schiebt die Geschwister weiter).
// - FromForm: Steuerelemente aus dem Formulartext (Formularmodell), für
//   Tests auf Fixture-DFMs ohne IDE.
// - TAtlasTabClicks: Modus „Reihenfolge klicken“: zählt je Elternelement ab
//   0 hoch, merkt den alten Stand für Esc.

interface

uses
  System.Types,
  System.Generics.Collections,
  Atlas.Core.Designer.FormModel;

type
  /// <summary>Steuerelement mit TabOrder für die Tab-Reihenfolge.</summary>
  TAtlasTabStop = record
    Name: string;
    ParentName: string;
    TabOrder: Integer;
    /// <summary>Lage im Client der Wurzel.</summary>
    Bounds: TRect;
    /// <summary>TabStop = True: Tab bleibt hier stehen.</summary>
    Focusable: Boolean;
    /// <summary>Hat Kinder (Panel, GroupBox, Frame, Registerseite): Tab führt hinein.</summary>
    Container: Boolean;
    /// <summary>Fokussierbar, ohne Kinder.</summary>
    class function Create(const AName, AParentName: string; ATabOrder: Integer;
      const ABounds: TRect): TAtlasTabStop; static;
    /// <summary>Erreicht Tab das Steuerelement oder seine Kinder?</summary>
    function Reached: Boolean;
  end;

{$SCOPEDENUMS ON}
  /// <summary>Auffälligkeit einer Marke; None = in Ordnung.</summary>
  TAtlasTabIssue = (None, Jump, Gap, Duplicate);
{$SCOPEDENUMS OFF}

  /// <summary>TabOrder := Order für das Steuerelement Name.</summary>
  TAtlasTabAssignment = record
    Name: string;
    Order: Integer;
    class function Create(const AName: string; AOrder: Integer): TAtlasTabAssignment; static;
  end;

  TAtlasTabOrder = class
  public
    /// <summary>Lesereihenfolge: A vor B? Gleiche Zeile, wenn sich die Höhen zur Hälfte überdecken; in der Zeile
    /// links zuerst, mit ARightToLeft rechts zuerst.</summary>
    class function ReadsBefore(const A, B: TRect; ARightToLeft: Boolean = False): Boolean; static;
    /// <summary>Je Stop: springt die Tab-Reihenfolge seines Elternelements hierher zurück (gegen die
    /// Lesereihenfolge)?</summary>
    class function OutOfOrder(const AStops: TArray<TAtlasTabStop>; ARightToLeft: Boolean = False): TArray<Boolean>;
      static;
    /// <summary>Je Stop die Auffälligkeit: Doppelte vor Lücken vor Rücksprüngen.</summary>
    class function Issues(const AStops: TArray<TAtlasTabStop>; ARightToLeft: Boolean = False): TArray<TAtlasTabIssue>;
      static;
    /// <summary>Je Stop der Pfad der TabOrder über die umschließenden Container („2.1“).</summary>
    class function Paths(const AStops: TArray<TAtlasTabStop>): TArray<string>; static;
    /// <summary>Je Stop die TabOrder nach der Lesereihenfolge in seinem Elternelement (0, 1, 2 …).</summary>
    class function ReadingOrder(const AStops: TArray<TAtlasTabStop>; ARightToLeft: Boolean = False): TArray<Integer>;
      static;
    /// <summary>Zuweisungen für den Stand AOrders (je Stop): je Elternelement aufsteigend, damit der Setter der
    /// VCL beim Weiterschieben genau diesen Stand ergibt. Ohne Änderung leer.</summary>
    class function Assignments(const AStops: TArray<TAtlasTabStop>; const AOrders: TArray<Integer>):
      TArray<TAtlasTabAssignment>; static;
    /// <summary>Steuerelemente mit TabOrder aus dem Formulartext; Lage über die Elternelemente aufsummiert.</summary>
    class function FromForm(const AObjects: TArray<TAtlasFormObject>): TArray<TAtlasTabStop>; static;
    /// <summary>Index des Stops AName ohne Groß-/Kleinschreibung; -1 ohne ihn.</summary>
    class function IndexOf(const AStops: TArray<TAtlasTabStop>; const AName: string): Integer; static;
  end;

  /// <summary>Modus „Reihenfolge klicken“: je Elternelement 0, 1, 2 …; der Stand vor dem ersten Klick bleibt für
  /// Esc.</summary>
  TAtlasTabClicks = class
  private
    FNext: TDictionary<string, Integer>;
    FClicked: TDictionary<string, Boolean>;
    FOriginal: TArray<TAtlasTabStop>;
    FActive: Boolean;
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>Modus beginnen; AStops ist der Stand für Esc.</summary>
    procedure Start(const AStops: TArray<TAtlasTabStop>);
    /// <summary>TabOrder für den Klick auf AName unter AParentName; -1, wenn AName schon geklickt ist.</summary>
    function Next(const AName, AParentName: string): Integer;
    /// <summary>Ist AName seit Start geklickt?</summary>
    function Clicked(const AName: string): Boolean;
    /// <summary>Zahl der Klicks seit Start.</summary>
    function Count: Integer;
    /// <summary>Zuweisungen, die den Stand vor dem ersten Klick wiederherstellen.</summary>
    function Restore: TArray<TAtlasTabAssignment>;
    /// <summary>Modus beenden (Enter bzw. nach Esc).</summary>
    procedure Reset;
    property Active: Boolean read FActive;
  end;

implementation

uses
  System.SysUtils,
  System.Math;

function Key(const AText: string): string;
begin
  Result := LowerCase(AText);
end;

{ TAtlasTabStop }

class function TAtlasTabStop.Create(const AName, AParentName: string; ATabOrder: Integer;
  const ABounds: TRect): TAtlasTabStop;
begin
  Result.Name := AName;
  Result.ParentName := AParentName;
  Result.TabOrder := ATabOrder;
  Result.Bounds := ABounds;
  Result.Focusable := True;
  Result.Container := False;
end;

function TAtlasTabStop.Reached: Boolean;
begin
  Result := Focusable or Container;
end;

{ TAtlasTabAssignment }

class function TAtlasTabAssignment.Create(const AName: string; AOrder: Integer): TAtlasTabAssignment;
begin
  Result.Name := AName;
  Result.Order := AOrder;
end;

{ TAtlasTabOrder }

class function TAtlasTabOrder.ReadsBefore(const A, B: TRect; ARightToLeft: Boolean): Boolean;
var
  mOverlap, mLower: Integer;
begin
  // Gleiche Zeile: Die Höhen überdecken sich mindestens zur Hälfte der kleineren.
  mOverlap := Min(A.Bottom, B.Bottom) - Max(A.Top, B.Top);
  mLower := Min(A.Height, B.Height);
  if (mLower > 0) and (mOverlap * 2 >= mLower) then
  begin
    if ARightToLeft then
    begin
      Result := A.Right > B.Right;
    end
    else
    begin
      Result := A.Left < B.Left;
    end;
  end
  else
  begin
    Result := A.Top < B.Top;
  end;
end;

/// <summary>Indizes von AStops nach Elternelement, dann TabOrder; bei Gleichstand nach Lage in der Liste.</summary>
function ByParentAndOrder(const AStops: TArray<TAtlasTabStop>): TArray<Integer>;
var
  mIndex, mInner, mValue: Integer;

  function Less(ALeft, ARight: Integer): Boolean;
  var
    mCompare: Integer;
  begin
    mCompare := CompareText(AStops[ALeft].ParentName, AStops[ARight].ParentName);
    if mCompare = 0 then
    begin
      mCompare := AStops[ALeft].TabOrder - AStops[ARight].TabOrder;
    end;
    if mCompare = 0 then
    begin
      mCompare := ALeft - ARight;
    end;
    Result := mCompare < 0;
  end;

begin
  SetLength(Result, Length(AStops));
  // Einfügen: stabil und für die wenigen Steuerelemente eines Formulars schnell genug.
  for mIndex := 0 to High(Result) do
  begin
    mValue := mIndex;
    mInner := mIndex - 1;
    while (mInner >= 0) and Less(mValue, Result[mInner]) do
    begin
      Result[mInner + 1] := Result[mInner];
      Dec(mInner);
    end;
    Result[mInner + 1] := mValue;
  end;
end;

class function TAtlasTabOrder.OutOfOrder(const AStops: TArray<TAtlasTabStop>; ARightToLeft: Boolean): TArray<Boolean>;
var
  mOrder: TArray<Integer>;
  mIndex, mPrevious: Integer;
begin
  SetLength(Result, Length(AStops));
  mOrder := ByParentAndOrder(AStops);
  mPrevious := -1;
  for mIndex := 0 to High(mOrder) do
  begin
    if not AStops[mOrder[mIndex]].Reached then
    begin
      Continue;
    end;
    // Rücksprung: Das nächste erreichte liegt in der Lesereihenfolge vor dem vorigen.
    if (mPrevious >= 0) and SameText(AStops[mPrevious].ParentName, AStops[mOrder[mIndex]].ParentName) and
      ReadsBefore(AStops[mOrder[mIndex]].Bounds, AStops[mPrevious].Bounds, ARightToLeft) then
    begin
      Result[mOrder[mIndex]] := True;
    end;
    mPrevious := mOrder[mIndex];
  end;
end;

class function TAtlasTabOrder.Issues(const AStops: TArray<TAtlasTabStop>;
  ARightToLeft: Boolean): TArray<TAtlasTabIssue>;
var
  mOrder: TArray<Integer>;
  mJumps: TArray<Boolean>;
  mIndex, mCurrent, mPrevious: Integer;
  mFirst: Boolean;
begin
  SetLength(Result, Length(AStops));
  mJumps := OutOfOrder(AStops, ARightToLeft);
  for mIndex := 0 to High(AStops) do
  begin
    if mJumps[mIndex] then
    begin
      Result[mIndex] := TAtlasTabIssue.Jump;
    end;
  end;
  mOrder := ByParentAndOrder(AStops);
  for mIndex := 0 to High(mOrder) do
  begin
    mCurrent := mOrder[mIndex];
    mFirst := (mIndex = 0) or not SameText(AStops[mOrder[mIndex - 1]].ParentName, AStops[mCurrent].ParentName);
    if mFirst then
    begin
      // Die Folge beginnt bei 0.
      if AStops[mCurrent].TabOrder > 0 then
      begin
        Result[mCurrent] := TAtlasTabIssue.Gap;
      end;
      Continue;
    end;
    mPrevious := mOrder[mIndex - 1];
    if AStops[mCurrent].TabOrder = AStops[mPrevious].TabOrder then
    begin
      Result[mCurrent] := TAtlasTabIssue.Duplicate;
      Result[mPrevious] := TAtlasTabIssue.Duplicate;
    end
    else if (AStops[mCurrent].TabOrder > AStops[mPrevious].TabOrder + 1) and
      (Result[mCurrent] <> TAtlasTabIssue.Duplicate) then
    begin
      Result[mCurrent] := TAtlasTabIssue.Gap;
    end;
  end;
end;

class function TAtlasTabOrder.IndexOf(const AStops: TArray<TAtlasTabStop>; const AName: string): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(AStops) do
  begin
    if SameText(AStops[mIndex].Name, AName) then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

class function TAtlasTabOrder.Paths(const AStops: TArray<TAtlasTabStop>): TArray<string>;
var
  mIndex, mParent, mGuard: Integer;
  mPath: string;
begin
  SetLength(Result, Length(AStops));
  for mIndex := 0 to High(AStops) do
  begin
    mPath := IntToStr(AStops[mIndex].TabOrder);
    mParent := IndexOf(AStops, AStops[mIndex].ParentName);
    // Schutz gegen Ringe in fehlerhaften Daten.
    mGuard := Length(AStops);
    while (mParent >= 0) and (mGuard > 0) do
    begin
      mPath := IntToStr(AStops[mParent].TabOrder) + '.' + mPath;
      mParent := IndexOf(AStops, AStops[mParent].ParentName);
      Dec(mGuard);
    end;
    Result[mIndex] := mPath;
  end;
end;

class function TAtlasTabOrder.ReadingOrder(const AStops: TArray<TAtlasTabStop>;
  ARightToLeft: Boolean): TArray<Integer>;
var
  mParents: TObjectDictionary<string, TList<Integer>>;
  mList: TList<Integer>;
  mIndex, mInner, mValue, mPosition: Integer;
begin
  SetLength(Result, Length(AStops));
  mParents := TObjectDictionary<string, TList<Integer>>.Create([doOwnsValues]);
  try
    for mIndex := 0 to High(AStops) do
    begin
      if not mParents.TryGetValue(Key(AStops[mIndex].ParentName), mList) then
      begin
        mList := TList<Integer>.Create;
        mParents.Add(Key(AStops[mIndex].ParentName), mList);
      end;
      // Einfügen nach Lesereihenfolge; Gleichstand bleibt in der Reihenfolge der Liste.
      mPosition := mList.Count;
      mInner := mList.Count - 1;
      while (mInner >= 0) and ReadsBefore(AStops[mIndex].Bounds, AStops[mList[mInner]].Bounds, ARightToLeft) do
      begin
        mPosition := mInner;
        Dec(mInner);
      end;
      mList.Insert(mPosition, mIndex);
    end;
    for mList in mParents.Values do
    begin
      for mValue := 0 to mList.Count - 1 do
      begin
        Result[mList[mValue]] := mValue;
      end;
    end;
  finally
    mParents.Free;
  end;
end;

class function TAtlasTabOrder.Assignments(const AStops: TArray<TAtlasTabStop>;
  const AOrders: TArray<Integer>): TArray<TAtlasTabAssignment>;
var
  mTarget: TArray<TAtlasTabStop>;
  mOrder: TArray<Integer>;
  mIndex: Integer;
  mChanged: Boolean;
begin
  Result := nil;
  mTarget := Copy(AStops);
  mChanged := False;
  for mIndex := 0 to High(mTarget) do
  begin
    mChanged := mChanged or (mTarget[mIndex].TabOrder <> AOrders[mIndex]);
    mTarget[mIndex].TabOrder := AOrders[mIndex];
  end;
  if not mChanged then
  begin
    Exit;
  end;
  // Aufsteigend je Elternelement: Jeder Setter schiebt nur noch nicht gesetzte Geschwister nach hinten.
  mOrder := ByParentAndOrder(mTarget);
  for mIndex := 0 to High(mOrder) do
  begin
    Result := Result + [TAtlasTabAssignment.Create(mTarget[mOrder[mIndex]].Name, mTarget[mOrder[mIndex]].TabOrder)];
  end;
end;

function NumberOf(const AObject: TAtlasFormObject; const APath: string): Integer;
var
  mText: string;
begin
  if not AObject.ValueOf(APath, mText) or not TryStrToInt(mText, Result) then
  begin
    Result := 0;
  end;
end;

/// <summary>Oben links des Objekts AIndex im Client der Wurzel.</summary>
function OriginOf(const AObjects: TArray<TAtlasFormObject>; AIndex: Integer): TPoint;
var
  mIndex, mGuard: Integer;
begin
  Result := Point(0, 0);
  mIndex := AIndex;
  mGuard := Length(AObjects);
  while (mIndex > 0) and (mGuard > 0) do
  begin
    Result.Offset(NumberOf(AObjects[mIndex], 'Left'), NumberOf(AObjects[mIndex], 'Top'));
    mIndex := TAtlasFormModel.IndexOf(AObjects, AObjects[mIndex].OwnerName);
    Dec(mGuard);
  end;
end;

function HasChildren(const AObjects: TArray<TAtlasFormObject>; const AName: string): Boolean;
var
  mObject: TAtlasFormObject;
begin
  for mObject in AObjects do
  begin
    if SameText(mObject.OwnerName, AName) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

class function TAtlasTabOrder.FromForm(const AObjects: TArray<TAtlasFormObject>): TArray<TAtlasTabStop>;
var
  mIndex, mOrder: Integer;
  mText, mParent: string;
  mOrigin: TPoint;
  mStop: TAtlasTabStop;
begin
  Result := nil;
  for mIndex := 1 to High(AObjects) do
  begin
    if not AObjects[mIndex].ValueOf('TabOrder', mText) or not TryStrToInt(mText, mOrder) then
    begin
      Continue;
    end;
    mParent := AObjects[mIndex].OwnerName;
    // Direkt auf dem Formular: Elternelement '' wie im Designer.
    if TAtlasFormModel.IndexOf(AObjects, mParent) = 0 then
    begin
      mParent := '';
    end;
    mOrigin := OriginOf(AObjects, mIndex);
    mStop := TAtlasTabStop.Create(AObjects[mIndex].Name, mParent, mOrder, Rect(mOrigin.X, mOrigin.Y,
      mOrigin.X + NumberOf(AObjects[mIndex], 'Width'), mOrigin.Y + NumberOf(AObjects[mIndex], 'Height')));
    mStop.Focusable := not (AObjects[mIndex].ValueOf('TabStop', mText) and SameText(mText, 'False'));
    mStop.Container := HasChildren(AObjects, AObjects[mIndex].Name);
    Result := Result + [mStop];
  end;
end;

{ TAtlasTabClicks }

constructor TAtlasTabClicks.Create;
begin
  inherited Create;
  FNext := TDictionary<string, Integer>.Create;
  FClicked := TDictionary<string, Boolean>.Create;
end;

destructor TAtlasTabClicks.Destroy;
begin
  FClicked.Free;
  FNext.Free;
  inherited Destroy;
end;

procedure TAtlasTabClicks.Start(const AStops: TArray<TAtlasTabStop>);
begin
  Reset;
  FOriginal := Copy(AStops);
  FActive := True;
end;

function TAtlasTabClicks.Next(const AName, AParentName: string): Integer;
begin
  if FClicked.ContainsKey(Key(AName)) then
  begin
    Exit(-1);
  end;
  FClicked.Add(Key(AName), True);
  if not FNext.TryGetValue(Key(AParentName), Result) then
  begin
    Result := 0;
  end;
  FNext.AddOrSetValue(Key(AParentName), Result + 1);
end;

function TAtlasTabClicks.Clicked(const AName: string): Boolean;
begin
  Result := FClicked.ContainsKey(Key(AName));
end;

function TAtlasTabClicks.Count: Integer;
begin
  Result := FClicked.Count;
end;

function TAtlasTabClicks.Restore: TArray<TAtlasTabAssignment>;
var
  mOrders: TArray<Integer>;
  mIndex: Integer;
  mCurrent: TArray<TAtlasTabStop>;
begin
  // Alle Zuweisungen des alten Stands, auch unveränderte: Die Klicks haben Geschwister verschoben.
  mCurrent := Copy(FOriginal);
  SetLength(mOrders, Length(mCurrent));
  for mIndex := 0 to High(mCurrent) do
  begin
    mOrders[mIndex] := mCurrent[mIndex].TabOrder;
    mCurrent[mIndex].TabOrder := -1;
  end;
  Result := TAtlasTabOrder.Assignments(mCurrent, mOrders);
end;

procedure TAtlasTabClicks.Reset;
begin
  FNext.Clear;
  FClicked.Clear;
  FOriginal := nil;
  FActive := False;
end;

end.
