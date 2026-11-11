unit Atlas.Core.Designer.InlineCaption;

// Beschriftung direkt im Designer bearbeiten (#748), reine Rechnung ohne IDE:
// - PropertyFor: welche Eigenschaft eine Klasse bearbeitet (Caption, Text,
//   EditLabel.Caption, Titel der Spalte bei DB-Grids); eigene Zuordnung aus
//   designer.inlineCaption.properties („TMyEdit=Text, TMyGrid=-“).
// - Order und Next: Tab-Reihenfolge der Komponenten mit Text nach TabOrder;
//   Labels stehen über FocusControl vor ihrem Feld, sonst nach ihrer Lage.
// - ColumnAt: Spalte eines Grids unter einem Punkt.
// - CanBreak und Duplicates: mehrzeilige Captions, doppelte Tastenkürzel.

interface

uses
  System.SysUtils;

type
  TAtlasCaptionStop = record
    Name: string;
    Parent: string;
    /// <summary>TabOrder von der Wurzel bis zur Komponente; leer bei Steuerelementen ohne Fenster (Labels).</summary>
    TabPath: TArray<Integer>;
    FocusControl: string;
    Top: Integer;
    Left: Integer;
    class function Create(const AName, AParent: string; const ATabPath: TArray<Integer>;
      const AFocusControl: string; ATop, ALeft: Integer): TAtlasCaptionStop; static;
  end;

  TAtlasInlineCaption = class
  public const
    /// <summary>Pfad des Spaltentitels; „*“ steht für den Index der Spalte (ColumnPath).</summary>
    cColumnTitle = 'Columns[*].Title.Caption';
    /// <summary>In der Zuordnung: Klasse ohne Bearbeitung.</summary>
    cNone = '-';
  public
    /// <summary>Eigenschaft für eine Komponente mit der Klassenkette AClassChain (eigene Klasse zuerst);
    /// AHasCaption: sie hat eine veröffentlichte Caption. Leer: keine Bearbeitung.</summary>
    class function PropertyFor(const AClassChain: TArray<string>; AHasCaption: Boolean;
      const AMap: string): string; static;
    /// <summary>Spaltentitel AIndex aus cColumnTitle.</summary>
    class function ColumnPath(AIndex: Integer): string; static;
    /// <summary>Text und TextHint tauschen (Strg+H); andere Pfade bleiben.</summary>
    class function Toggled(const APath: string): string; static;
    /// <summary>Namen in Tab-Reihenfolge.</summary>
    class function Order(const AStops: TArray<TAtlasCaptionStop>): TArray<string>; static;
    /// <summary>Nächster (ABack: vorheriger) Name nach ACurrent in AOrder, am Ende wieder vorn; leer, wenn es
    /// keinen anderen gibt.</summary>
    class function Next(const AOrder: TArray<string>; const ACurrent: string; ABack: Boolean): string; static;
    /// <summary>Spalte unter AX (Client des Grids); AStart: Breite des Indikators, ALine: Breite der Linien.
    /// -1 außerhalb.</summary>
    class function ColumnAt(AX: Integer; const AWidths: TArray<Integer>; AStart, ALine: Integer): Integer; static;
    /// <summary>Darf Umschalt+Enter einen Zeilenumbruch einfügen?</summary>
    class function CanBreak(AWordWrap: Boolean; const AText: string): Boolean; static;
    /// <summary>Indizes der anderen Texte mit demselben Tastenkürzel wie ATexts[AIndex].</summary>
    class function Duplicates(const ATexts: TArray<string>; AIndex: Integer): TArray<Integer>; static;
    /// <summary>Breite des Eingabefelds: mindestens die der Komponente, sonst Text und Rand.</summary>
    class function EditorWidth(AComponentWidth, ATextWidth, APadding: Integer): Integer; static;
  end;

implementation

uses
  System.Math,
  Atlas.Core.Designer.FormTexts;

{ TAtlasCaptionStop }

class function TAtlasCaptionStop.Create(const AName, AParent: string; const ATabPath: TArray<Integer>;
  const AFocusControl: string; ATop, ALeft: Integer): TAtlasCaptionStop;
begin
  Result.Name := AName;
  Result.Parent := AParent;
  Result.TabPath := ATabPath;
  Result.FocusControl := AFocusControl;
  Result.Top := ATop;
  Result.Left := ALeft;
end;

{ TAtlasInlineCaption }

const
  cBuiltIn: array [0 .. 6] of string = ('TCustomMemo=-', 'TMenuItem=-', 'TCustomLabeledEdit=EditLabel.Caption',
    'TCustomEdit=Text', 'TCustomComboBox=Text', 'TCustomDBGrid=' + TAtlasInlineCaption.cColumnTitle,
    'TCustomStaticText=Caption');

function Lookup(const AEntries: TArray<string>; const AClassName: string; out APath: string): Boolean;
var
  mEntry: string;
  mPos: Integer;
begin
  Result := False;
  for mEntry in AEntries do
  begin
    mPos := Pos('=', mEntry);
    if (mPos > 1) and SameText(Trim(Copy(mEntry, 1, mPos - 1)), AClassName) then
    begin
      APath := Trim(Copy(mEntry, mPos + 1, MaxInt));
      Exit(True);
    end;
  end;
end;

function Entries(const AMap: string): TArray<string>;
begin
  Result := AMap.Split([',', ';']);
end;

class function TAtlasInlineCaption.PropertyFor(const AClassChain: TArray<string>; AHasCaption: Boolean;
  const AMap: string): string;
var
  mClass: string;
  mUser, mBuiltIn: TArray<string>;
  mIndex: Integer;
begin
  mUser := Entries(AMap);
  mBuiltIn := nil;
  for mIndex := Low(cBuiltIn) to High(cBuiltIn) do
  begin
    mBuiltIn := mBuiltIn + [cBuiltIn[mIndex]];
  end;
  for mClass in AClassChain do
  begin
    if Lookup(mUser, mClass, Result) or Lookup(mBuiltIn, mClass, Result) then
    begin
      if Result = cNone then
      begin
        Result := '';
      end;
      Exit;
    end;
  end;
  Result := '';
  if AHasCaption then
  begin
    Result := 'Caption';
  end;
end;

class function TAtlasInlineCaption.ColumnPath(AIndex: Integer): string;
begin
  Result := StringReplace(cColumnTitle, '*', IntToStr(AIndex), []);
end;

class function TAtlasInlineCaption.Toggled(const APath: string): string;
begin
  Result := APath;
  if SameText(APath, 'Text') then
  begin
    Result := 'TextHint';
  end
  else if SameText(APath, 'TextHint') then
  begin
    Result := 'Text';
  end;
end;

/// <summary>Kommt der Tab-Pfad A vor B? Ein Container (kürzerer Pfad) vor seinem Inhalt.</summary>
function PathBefore(const A, B: TArray<Integer>): Boolean;
var
  mIndex: Integer;
begin
  for mIndex := 0 to Min(High(A), High(B)) do
  begin
    if A[mIndex] <> B[mIndex] then
    begin
      Exit(A[mIndex] < B[mIndex]);
    end;
  end;
  Result := Length(A) < Length(B);
end;

function PlaceBefore(const A, B: TAtlasCaptionStop): Boolean;
begin
  Result := (A.Top < B.Top) or ((A.Top = B.Top) and (A.Left < B.Left));
end;

/// <summary>Stabil sortiert: Steuerelemente mit Fenster nach Tab-Pfad, die anderen nach Lage.</summary>
function Sorted(const AStops: TArray<TAtlasCaptionStop>; AWindowed: Boolean): TArray<TAtlasCaptionStop>;
var
  mStop: TAtlasCaptionStop;
  mIndex: Integer;
begin
  Result := nil;
  for mStop in AStops do
  begin
    if (Length(mStop.TabPath) > 0) <> AWindowed then
    begin
      Continue;
    end;
    mIndex := Length(Result);
    while (mIndex > 0) and ((AWindowed and PathBefore(mStop.TabPath, Result[mIndex - 1].TabPath)) or
      (not AWindowed and PlaceBefore(mStop, Result[mIndex - 1]))) do
    begin
      Dec(mIndex);
    end;
    Insert(mStop, Result, mIndex);
  end;
end;

function IndexOfName(const AStops: TArray<TAtlasCaptionStop>; const AName: string): Integer;
begin
  for Result := 0 to High(AStops) do
  begin
    if SameText(AStops[Result].Name, AName) then
    begin
      Exit;
    end;
  end;
  Result := -1;
end;

/// <summary>Index nach AIndex und allem, was in AList[AIndex] liegt (auch tiefer).</summary>
function AfterContent(const AList: TArray<TAtlasCaptionStop>; AIndex: Integer): Integer;
var
  mInside: TArray<string>;
  mName: string;
  mFound: Boolean;
begin
  mInside := [AList[AIndex].Name];
  Result := AIndex + 1;
  mFound := True;
  while mFound and (Result <= High(AList)) do
  begin
    mFound := False;
    for mName in mInside do
    begin
      mFound := mFound or SameText(AList[Result].Parent, mName);
    end;
    if mFound then
    begin
      mInside := mInside + [AList[Result].Name];
      Inc(Result);
    end;
  end;
end;

/// <summary>Platz für ein Label ohne FocusControl: vor dem ersten Geschwister mit Fenster, das nach ihm kommt,
/// sonst nach dem letzten Geschwister und dessen Inhalt, sonst nach dem Parent, sonst am Ende.</summary>
function SlotOf(const AList: TArray<TAtlasCaptionStop>; const ALabel: TAtlasCaptionStop): Integer;
var
  mIndex: Integer;
begin
  Result := -1;
  for mIndex := 0 to High(AList) do
  begin
    if SameText(AList[mIndex].Parent, ALabel.Parent) then
    begin
      if (Length(AList[mIndex].TabPath) > 0) and PlaceBefore(ALabel, AList[mIndex]) then
      begin
        Exit(mIndex);
      end;
      Result := AfterContent(AList, mIndex);
    end;
  end;
  if Result < 0 then
  begin
    Result := IndexOfName(AList, ALabel.Parent) + 1;
  end;
  if Result <= 0 then
  begin
    Result := Length(AList);
  end;
end;

class function TAtlasInlineCaption.Order(const AStops: TArray<TAtlasCaptionStop>): TArray<string>;
var
  mList: TArray<TAtlasCaptionStop>;
  mLabel: TAtlasCaptionStop;
  mSlot: Integer;
begin
  mList := Sorted(AStops, True);
  for mLabel in Sorted(AStops, False) do
  begin
    mSlot := -1;
    if mLabel.FocusControl <> '' then
    begin
      mSlot := IndexOfName(mList, mLabel.FocusControl);
    end;
    if mSlot < 0 then
    begin
      mSlot := SlotOf(mList, mLabel);
    end;
    Insert(mLabel, mList, mSlot);
  end;
  Result := nil;
  for mLabel in mList do
  begin
    Result := Result + [mLabel.Name];
  end;
end;

class function TAtlasInlineCaption.Next(const AOrder: TArray<string>; const ACurrent: string;
  ABack: Boolean): string;
var
  mIndex, mStep: Integer;
begin
  Result := '';
  mIndex := High(AOrder);
  while (mIndex >= 0) and not SameText(AOrder[mIndex], ACurrent) do
  begin
    Dec(mIndex);
  end;
  if (mIndex < 0) or (Length(AOrder) < 2) then
  begin
    Exit;
  end;
  mStep := 1;
  if ABack then
  begin
    mStep := -1;
  end;
  Result := AOrder[(mIndex + mStep + Length(AOrder)) mod Length(AOrder)];
end;

class function TAtlasInlineCaption.ColumnAt(AX: Integer; const AWidths: TArray<Integer>; AStart,
  ALine: Integer): Integer;
var
  mLeft: Integer;
begin
  mLeft := AStart;
  for Result := 0 to High(AWidths) do
  begin
    if (AX >= mLeft) and (AX < mLeft + AWidths[Result] + ALine) then
    begin
      Exit;
    end;
    mLeft := mLeft + AWidths[Result] + ALine;
  end;
  Result := -1;
end;

class function TAtlasInlineCaption.CanBreak(AWordWrap: Boolean; const AText: string): Boolean;
begin
  Result := AWordWrap or (Pos(#10, AText) > 0) or (Pos(#13, AText) > 0);
end;

class function TAtlasInlineCaption.Duplicates(const ATexts: TArray<string>; AIndex: Integer): TArray<Integer>;
var
  mKey: Char;
  mIndex: Integer;
begin
  Result := nil;
  if (AIndex < 0) or (AIndex > High(ATexts)) then
  begin
    Exit;
  end;
  mKey := TAtlasFormTexts.AcceleratorOf(ATexts[AIndex]);
  if mKey = #0 then
  begin
    Exit;
  end;
  for mIndex := 0 to High(ATexts) do
  begin
    if (mIndex <> AIndex) and (TAtlasFormTexts.AcceleratorOf(ATexts[mIndex]) = mKey) then
    begin
      Result := Result + [mIndex];
    end;
  end;
end;

class function TAtlasInlineCaption.EditorWidth(AComponentWidth, ATextWidth, APadding: Integer): Integer;
begin
  Result := AComponentWidth;
  if ATextWidth + APadding > Result then
  begin
    Result := ATextWidth + APadding;
  end;
end;

end.
