unit Atlas.Core.Designer.ExtractFrame;

// Auswahl in einen Frame auslagern (#611), ohne VCL und Windows, auf dem Text
// von Formular-DFM und Formular-Unit:
// - Auswahl: Komponenten mit demselben Parent oder ein Container, dessen
//   Kinder zum Frame werden (ContainerAsFrame). Der Frame übernimmt die Lage
//   (Rechteck um die Auswahl bzw. der Container) sowie Align und Anchors, wenn
//   es genau eine Komponente bzw. der Container ist; die Kinder rücken um die
//   linke obere Ecke nach links oben.
// - Formular-DFM: die erste Auswahl wird zu „inline frmAdresse: TfrmAdresse“,
//   die übrigen entfallen. Handler, die im Formular bleiben, verbindet ein
//   „inherited“-Block im inline-Block (wie die IDE es schreibt).
// - Handler wandern mit (MoveHandlers), wenn nur verschobene Komponenten sie
//   nutzen und der Formular-Code sie nicht aufruft; sonst bleiben sie mit
//   Hinweis. Greift ein mitwandernder Handler auf ein Feld des Formulars zu,
//   das bleibt, steht das als Problem in den Hinweisen.
// - Formular-Unit: Felder und Handler der verschobenen Komponenten entfallen,
//   dazu ein Feld für den Frame, die Frame-Unit in den uses; Zugriffe im Code
//   (edtName.Text) werden zu frmAdresse.edtName.Text, ohne Zeichenketten und
//   Kommentare.
// - Frame-Unit: Klasse mit den Feldern und mitwandernden Handlern; uses wie
//   im Formular, Vcl.Forms ergänzt.

interface

uses
  System.Types;

type
  TAtlasExtractOptions = record
    /// <summary>Namen der markierten Komponenten (direkt, nicht ihre Kinder).</summary>
    Names: TArray<string>;
    FrameClass: string;
    FrameUnit: string;
    InstanceName: string;
    MoveHandlers: Boolean;
    /// <summary>Genau ein Container markiert: seine Kinder werden zum Frame, er selbst entfällt.</summary>
    ContainerAsFrame: Boolean;
  end;

  TAtlasExtractResult = record
    FormDfm: string;
    FormUnit: string;
    FrameDfm: string;
    FrameUnit: string;
    /// <summary>Komponenten im Frame (auch Kinder).</summary>
    Moved: TArray<string>;
    MovedHandlers: TArray<string>;
    KeptHandlers: TArray<string>;
    /// <summary>Hinweise in der Vorschau; Platzhalter-Texte siehe TAtlasExtractNote.</summary>
    Notes: TArray<string>;
    /// <summary>Leer, wenn das Auslagern möglich ist; sonst der Grund.</summary>
    Error: string;
  end;

  /// <summary>Kennungen der Hinweise; die Texte setzt die Oberfläche ein (Text|Arg1|Arg2).</summary>
  TAtlasExtractNote = class
  public const
    cKept = 'kept';
    cFormField = 'formField';
    cContainerProps = 'containerProps';
    cErrNothing = 'nothing';
    cErrParents = 'parents';
    cErrNotFound = 'notFound';
    cErrClass = 'class';
    cErrName = 'name';
  end;

  TAtlasExtractFrame = class
  public
    /// <summary>Alle Änderungen für AOptions; AFormClass ist die Klasse des Formulars (TfrmKunden).</summary>
    class function Run(const AFormDfm, AFormUnit, AFormClass: string; const AOptions: TAtlasExtractOptions)
      : TAtlasExtractResult; static;
    /// <summary>Vorschlag für den Frame-Namen aus der ersten Komponente (pnlAdresse → Adresse).</summary>
    class function Suggest(const AName: string; out AFrameClass, AFrameUnit, AInstance: string): Boolean; static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Atlas.Core.Designer.NameSuggest,
  Atlas.Core.Designer.FormUnit;

type
  TNode = record
    Name: string;
    ClassName: string;
    Indent: Integer;
    First: Integer;
    Last: Integer;
    Parent: Integer;
    /// <summary>Letzte Zeile der eigenen Eigenschaften (vor dem ersten Kind bzw. vor „end“).</summary>
    PropsLast: Integer;
  end;

  TDfm = record
    Lines: TArray<string>;
    Nodes: TArray<TNode>;
    function IndexOf(const AName: string): Integer;
    function IsInside(ANode, AAncestor: Integer): Boolean;
    function Value(ANode: Integer; const AProp: string; out AValue: string): Boolean;
  end;

const
  cFrameIndent = 2;
  cCrLf = #13#10;
  cAssign = ' = ';
  /// <summary>Unbekannter Parent (vor der ersten Komponente); -1 ist das Formular selbst.</summary>
  cNoParent = -2;
  cPropLine = '%s%s = %s';
  cObjectHead = '%sobject %s: %s';
  cInlineHead = '%sinline %s: %s';
  cInheritedHead = '%sinherited %s: %s';
  cClassHead = '  %s = class(TFrame)';
  cUnitHead = 'unit %s;';

function HeaderOf(const ALine: string; out AName, AClassName: string): Boolean;
var
  mText, mWord: string;
  mColon: Integer;
begin
  mText := ALine.Trim;
  Result := StartsText('object ', mText) or StartsText('inherited ', mText) or StartsText('inline ', mText);
  if not Result then
  begin
    Exit;
  end;
  mWord := Copy(mText, Pos(' ', mText) + 1, MaxInt);
  mColon := Pos(':', mWord);
  Result := mColon > 0;
  AName := Copy(mWord, 1, mColon - 1).Trim;
  AClassName := Copy(mWord, mColon + 1, MaxInt).Trim;
  if Pos(' ', AClassName) > 0 then
  begin
    AClassName := Copy(AClassName, 1, Pos(' ', AClassName) - 1);
  end;
end;

/// <summary>Eigene Eigenschaften des obersten Knotens enden vor ALine (erstes Kind bzw. „end“).</summary>
procedure EndProps(var ADfm: TDfm; const AStack: TArray<Integer>; ALine: Integer);
var
  mTop: Integer;
begin
  if Length(AStack) = 0 then
  begin
    Exit;
  end;
  mTop := AStack[High(AStack)];
  if ADfm.Nodes[mTop].PropsLast < 0 then
  begin
    ADfm.Nodes[mTop].PropsLast := ALine - 1;
  end;
end;

procedure OpenNode(var ADfm: TDfm; var AStack: TArray<Integer>; ALine: Integer; const AName, AClassName: string);
var
  mNode: TNode;
begin
  EndProps(ADfm, AStack, ALine);
  mNode := Default(TNode);
  mNode.Name := AName;
  mNode.ClassName := AClassName;
  mNode.Indent := TAtlasFormUnit.SpacesOf(ADfm.Lines[ALine]);
  mNode.First := ALine;
  mNode.Last := -1;
  mNode.PropsLast := -1;
  mNode.Parent := -1;
  if Length(AStack) > 0 then
  begin
    mNode.Parent := AStack[High(AStack)];
  end;
  ADfm.Nodes := ADfm.Nodes + [mNode];
  AStack := AStack + [High(ADfm.Nodes)];
end;

/// <summary>Schließt den obersten Knoten, wenn ALine sein „end“ ist.</summary>
procedure CloseNode(var ADfm: TDfm; var AStack: TArray<Integer>; ALine: Integer);
var
  mTop: Integer;
begin
  if (Length(AStack) = 0) or (ADfm.Lines[ALine].Trim <> 'end') then
  begin
    Exit;
  end;
  mTop := AStack[High(AStack)];
  if TAtlasFormUnit.SpacesOf(ADfm.Lines[ALine]) <> ADfm.Nodes[mTop].Indent then
  begin
    Exit;
  end;
  ADfm.Nodes[mTop].Last := ALine;
  EndProps(ADfm, AStack, ALine);
  SetLength(AStack, Length(AStack) - 1);
end;

function ParseDfm(const AText: string): TDfm;
var
  mStack: TArray<Integer>;
  mIndex: Integer;
  mName, mClass: string;
begin
  Result.Lines := AText.Replace(cCrLf, #10).Split([#10]);
  Result.Nodes := nil;
  mStack := nil;
  for mIndex := 0 to High(Result.Lines) do
  begin
    if HeaderOf(Result.Lines[mIndex], mName, mClass) then
    begin
      OpenNode(Result, mStack, mIndex, mName, mClass);
    end
    else
    begin
      CloseNode(Result, mStack, mIndex);
    end;
  end;
end;

function TDfm.IndexOf(const AName: string): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(Nodes) do
  begin
    if SameText(Nodes[mIndex].Name, AName) then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

function TDfm.IsInside(ANode, AAncestor: Integer): Boolean;
begin
  Result := False;
  while ANode >= 0 do
  begin
    if ANode = AAncestor then
    begin
      Exit(True);
    end;
    ANode := Nodes[ANode].Parent;
  end;
end;

function TDfm.Value(ANode: Integer; const AProp: string; out AValue: string): Boolean;
var
  mIndex: Integer;
  mLine: string;
begin
  for mIndex := Nodes[ANode].First + 1 to Nodes[ANode].PropsLast do
  begin
    mLine := Lines[mIndex];
    if (TAtlasFormUnit.SpacesOf(mLine) = Nodes[ANode].Indent + cFrameIndent) and
      StartsText(AProp + cAssign, mLine.Trim) then
    begin
      AValue := Copy(mLine.Trim, Length(AProp + cAssign) + 1, MaxInt);
      Exit(True);
    end;
  end;
  AValue := '';
  Result := False;
end;

function IntValue(const ADfm: TDfm; ANode: Integer; const AProp: string): Integer;
var
  mValue: string;
begin
  Result := 0;
  if ADfm.Value(ANode, AProp, mValue) then
  begin
    Result := StrToIntDef(mValue, 0);
  end;
end;

function Contains(const AList: TArray<string>; const AName: string): Boolean;
var
  mItem: string;
begin
  for mItem in AList do
  begin
    if SameText(mItem, AName) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Ereignis-Zeile „OnChange = edtPlzChange“: Handler; sonst ''.</summary>
function EventHandler(const ALine: string): string;
var
  mText: string;
  mEq: Integer;
begin
  Result := '';
  mText := ALine.Trim;
  mEq := Pos(cAssign, mText);
  if StartsText('On', mText) and (mEq > 0) and IsValidIdent(Copy(mText, mEq + Length(cAssign), MaxInt)) then
  begin
    Result := Copy(mText, mEq + Length(cAssign), MaxInt);
  end;
end;

{ Aufteilen }

type
  TSplit = record
    /// <summary>Knoten, deren Zeilen in den Frame gehen (Container-Fall: seine Kinder).</summary>
    Roots: TArray<Integer>;
    /// <summary>Knoten, die im Formular ersetzt bzw. entfernt werden.</summary>
    Removed: TArray<Integer>;
    Bounds: TRect;
    Align: string;
    Anchors: string;
  end;

function BoundsOf(const ADfm: TDfm; ANode: Integer): TRect;
begin
  Result := Bounds(IntValue(ADfm, ANode, 'Left'), IntValue(ADfm, ANode, 'Top'), IntValue(ADfm, ANode, 'Width'),
    IntValue(ADfm, ANode, 'Height'));
end;

function ChildrenOf(const ADfm: TDfm; ANode: Integer): TArray<Integer>;
var
  mChild: Integer;
begin
  Result := nil;
  for mChild := 0 to High(ADfm.Nodes) do
  begin
    if ADfm.Nodes[mChild].Parent = ANode then
    begin
      Result := Result + [mChild];
    end;
  end;
end;

/// <summary>Markierte Knoten mit gemeinsamem Rechteck; '' oder der Fehler.</summary>
function SelectedOf(const ADfm: TDfm; const ANames: TArray<string>; var ASplit: TSplit): string;
var
  mName: string;
  mNode, mParent: Integer;
begin
  Result := '';
  mParent := cNoParent;
  for mName in ANames do
  begin
    mNode := ADfm.IndexOf(mName);
    if mNode <= 0 then
    begin
      Exit(TAtlasExtractNote.cErrNotFound + '|' + mName);
    end;
    if (mParent <> cNoParent) and (ADfm.Nodes[mNode].Parent <> mParent) then
    begin
      Exit(TAtlasExtractNote.cErrParents);
    end;
    mParent := ADfm.Nodes[mNode].Parent;
    ASplit.Removed := ASplit.Removed + [mNode];
    if Length(ASplit.Removed) = 1 then
    begin
      ASplit.Bounds := BoundsOf(ADfm, mNode);
    end
    else
    begin
      ASplit.Bounds.Union(BoundsOf(ADfm, mNode));
    end;
  end;
end;

function SplitOf(const ADfm: TDfm; const AOptions: TAtlasExtractOptions; out ASplit: TSplit): string;
begin
  ASplit := Default(TSplit);
  if Length(AOptions.Names) = 0 then
  begin
    Exit(TAtlasExtractNote.cErrNothing);
  end;
  Result := SelectedOf(ADfm, AOptions.Names, ASplit);
  if Result <> '' then
  begin
    Exit;
  end;
  ASplit.Roots := ASplit.Removed;
  if Length(ASplit.Removed) = 1 then
  begin
    ADfm.Value(ASplit.Removed[0], 'Align', ASplit.Align);
    ADfm.Value(ASplit.Removed[0], 'Anchors', ASplit.Anchors);
    if AOptions.ContainerAsFrame then
    begin
      ASplit.Roots := ChildrenOf(ADfm, ASplit.Removed[0]);
    end;
  end;
end;

function MovedNames(const ADfm: TDfm; const ASplit: TSplit): TArray<string>;
var
  mNode, mRoot: Integer;
begin
  Result := nil;
  for mNode := 0 to High(ADfm.Nodes) do
  begin
    for mRoot in ASplit.Roots do
    begin
      if ADfm.IsInside(mNode, mRoot) then
      begin
        Result := Result + [ADfm.Nodes[mNode].Name];
        Break;
      end;
    end;
  end;
end;

function InRoots(const ADfm: TDfm; const ASplit: TSplit; ALine: Integer): Boolean;
var
  mRoot: Integer;
begin
  for mRoot in ASplit.Roots do
  begin
    if (ALine >= ADfm.Nodes[mRoot].First) and (ALine <= ADfm.Nodes[mRoot].Last) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function InRemoved(const ADfm: TDfm; const ASplit: TSplit; ALine: Integer): Boolean;
var
  mNode: Integer;
begin
  for mNode in ASplit.Removed do
  begin
    if (ALine >= ADfm.Nodes[mNode].First) and (ALine <= ADfm.Nodes[mNode].Last) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

{ Unit }

function AddToUses(const AUnit: TAtlasFormUnit; const AUnitName: string): TAtlasFormUnit;
var
  mIndex, mUses: Integer;
begin
  Result := AUnit;
  mUses := -1;
  for mIndex := 0 to Result.ImplementationLine - 1 do
  begin
    if (mUses < 0) and (SameText(Result.Lines[mIndex].Trim, 'uses') or StartsText('uses ', Result.Lines[mIndex].Trim)) then
    begin
      mUses := mIndex;
    end;
    if (mUses >= 0) and EndsText(';', Result.Lines[mIndex].TrimRight) then
    begin
      Result.Lines[mIndex] := Copy(Result.Lines[mIndex], 1, Length(Result.Lines[mIndex].TrimRight) - 1) + ',';
      Insert('  ' + AUnitName + ';', Result.Lines, mIndex + 1);
      Exit;
    end;
  end;
end;

/// <summary>Bezeichner im Text AText (ohne Zeichenketten und Kommentare), die Felder aus AFields sind.</summary>
function UsedFields(const AText: string; const AFields: TArray<string>): TArray<string>;
var
  mField: string;
begin
  Result := nil;
  for mField in AFields do
  begin
    if Length(TAtlasNameSuggest.Places(AText, mField)) > 0 then
    begin
      Result := Result + [mField];
    end;
  end;
end;

/// <summary>Zugriffe auf AName im Text ab Zeile AFrom mit APrefix versehen (nicht nach „x.“ außer „Self.“).
/// </summary>
procedure Prefix(var AUnit: TAtlasFormUnit; AFrom: Integer; const AName, APrefix: string);
var
  mPlaces: TArray<TAtlasNamePlace>;
  mIndex: Integer;
  mLine, mBefore: string;
begin
  mPlaces := TAtlasNameSuggest.Places(AUnit.Text, AName);
  for mIndex := High(mPlaces) downto 0 do
  begin
    if mPlaces[mIndex].Line < AFrom then
    begin
      Continue;
    end;
    mLine := AUnit.Lines[mPlaces[mIndex].Line];
    mBefore := Copy(mLine, 1, mPlaces[mIndex].Character).TrimRight;
    if EndsText('.', mBefore) and not EndsText('Self.', mBefore) then
    begin
      Continue;
    end;
    Insert(APrefix + '.', mLine, mPlaces[mIndex].Character + 1);
    AUnit.Lines[mPlaces[mIndex].Line] := mLine;
  end;
end;

function UsesLines(const AUnit: TAtlasFormUnit): TArray<string>;
var
  mIndex: Integer;
  mIn: Boolean;
begin
  Result := nil;
  mIn := False;
  for mIndex := 0 to AUnit.ImplementationLine - 1 do
  begin
    if SameText(AUnit.Lines[mIndex].Trim, 'uses') then
    begin
      mIn := True;
    end
    else if mIn then
    begin
      Result := Result + [AUnit.Lines[mIndex]];
      if EndsText(';', AUnit.Lines[mIndex].TrimRight) then
      begin
        Exit;
      end;
    end;
  end;
end;

function HasUnit(const AUses: TArray<string>; const AName: string): Boolean;
var
  mLine: string;
begin
  for mLine in AUses do
  begin
    if SameText(mLine.Trim.TrimRight([',', ';']), AName) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function FrameUnitText(const AOptions: TAtlasExtractOptions; const AUses, AFields, ADecls,
  ABodies: TArray<string>): string;
var
  mLines, mUses: TArray<string>;
  mLine: string;
begin
  mUses := AUses;
  if Length(mUses) = 0 then
  begin
    mUses := ['  Vcl.Forms;'];
  end
  else if not HasUnit(mUses, 'Vcl.Forms') and not HasUnit(mUses, 'Forms') then
  begin
    mUses[High(mUses)] := mUses[High(mUses)].TrimRight.TrimRight([';']) + ',';
    mUses := mUses + ['  Vcl.Forms;'];
  end;
  mLines := [Format(cUnitHead, [AOptions.FrameUnit]), '', 'interface', '', 'uses'] + mUses +
    ['', 'type', Format(cClassHead, [AOptions.FrameClass])];
  for mLine in AFields + ADecls do
  begin
    mLines := mLines + ['    ' + mLine.Trim];
  end;
  mLines := mLines + ['  end;', '', 'implementation', '', '{$R *.dfm}', ''];
  for mLine in ABodies do
  begin
    mLines := mLines + [mLine];
  end;
  mLines := mLines + ['end.', ''];
  Result := string.Join(cCrLf, mLines);
end;

{ DFM-Texte }

function Reindented(const ALine: string; AIndent: Integer): string;
begin
  Result := StringOfChar(' ', AIndent) + ALine.TrimLeft;
end;

function ShiftedLine(const ALine, AProp: string; ADelta: Integer; out AResult: string): Boolean;
var
  mText: string;
begin
  mText := ALine.Trim;
  Result := StartsText(AProp + ' = ', mText);
  if Result then
  begin
    AResult := Format(cPropLine, [StringOfChar(' ', TAtlasFormUnit.SpacesOf(ALine)), AProp,
      IntToStr(StrToIntDef(Copy(mText, Length(AProp + cAssign) + 1, MaxInt), 0) - ADelta)]);
  end;
end;

function FrameDfmText(const ADfm: TDfm; const ASplit: TSplit; const AOptions: TAtlasExtractOptions;
  const AKept: TArray<string>): string;
var
  mLines: TArray<string>;
  mRoot, mIndex, mDx, mDy: Integer;
  mLine, mShifted: string;
  mOwnProps: Boolean;
begin
  mDx := ASplit.Bounds.Left;
  mDy := ASplit.Bounds.Top;
  if AOptions.ContainerAsFrame then
  begin
    mDx := 0;
    mDy := 0;
  end;
  mLines := [Format(cObjectHead, ['', AOptions.InstanceName, AOptions.FrameClass]),
    Format(cPropLine, ['  ', 'Left', '0']), Format(cPropLine, ['  ', 'Top', '0']),
    Format(cPropLine, ['  ', 'Width', IntToStr(ASplit.Bounds.Width)]),
    Format(cPropLine, ['  ', 'Height', IntToStr(ASplit.Bounds.Height)]), Format(cPropLine, ['  ', 'TabOrder', '0'])];
  for mRoot in ASplit.Roots do
  begin
    for mIndex := ADfm.Nodes[mRoot].First to ADfm.Nodes[mRoot].Last do
    begin
      mLine := ADfm.Lines[mIndex];
      // Handler, die im Formular bleiben, verbindet der inherited-Block im Formular.
      if Contains(AKept, EventHandler(mLine)) then
      begin
        Continue;
      end;
      mOwnProps := (mIndex <= ADfm.Nodes[mRoot].PropsLast) and
        (TAtlasFormUnit.SpacesOf(mLine) = ADfm.Nodes[mRoot].Indent + cFrameIndent);
      if mOwnProps and (ShiftedLine(mLine, 'Left', mDx, mShifted) or ShiftedLine(mLine, 'Top', mDy, mShifted) or
        ShiftedLine(mLine, 'ExplicitLeft', mDx, mShifted) or ShiftedLine(mLine, 'ExplicitTop', mDy, mShifted)) then
      begin
        mLine := mShifted;
      end;
      mLines := mLines + [Reindented(mLine, cFrameIndent + TAtlasFormUnit.SpacesOf(mLine) - ADfm.Nodes[mRoot].Indent)];
    end;
  end;
  mLines := mLines + ['end', ''];
  Result := string.Join(cCrLf, mLines);
end;

/// <summary>inherited-Blöcke für die Ereignisse der Handler AKept, verschachtelt wie im Frame.</summary>
function InheritedLines(const ADfm: TDfm; const ASplit: TSplit; ANode, AIndent: Integer;
  const AKept: TArray<string>): TArray<string>;
var
  mIndex, mChild: Integer;
  mOwn, mInner: TArray<string>;
begin
  Result := nil;
  mOwn := nil;
  for mIndex := ADfm.Nodes[ANode].First + 1 to ADfm.Nodes[ANode].PropsLast do
  begin
    if (TAtlasFormUnit.SpacesOf(ADfm.Lines[mIndex]) = ADfm.Nodes[ANode].Indent + cFrameIndent) and
      Contains(AKept, EventHandler(ADfm.Lines[mIndex])) then
    begin
      mOwn := mOwn + [StringOfChar(' ', AIndent + cFrameIndent) + ADfm.Lines[mIndex].Trim];
    end;
  end;
  mInner := nil;
  for mChild := 0 to High(ADfm.Nodes) do
  begin
    if ADfm.Nodes[mChild].Parent = ANode then
    begin
      mInner := mInner + InheritedLines(ADfm, ASplit, mChild, AIndent + cFrameIndent, AKept);
    end;
  end;
  if (Length(mOwn) > 0) or (Length(mInner) > 0) then
  begin
    Result := [Format(cInheritedHead, [StringOfChar(' ', AIndent), ADfm.Nodes[ANode].Name,
      ADfm.Nodes[ANode].ClassName])] + mOwn + mInner + [StringOfChar(' ', AIndent) + 'end'];
  end;
end;

function FormDfmText(const ADfm: TDfm; const ASplit: TSplit; const AOptions: TAtlasExtractOptions;
  const AKept: TArray<string>): string;
var
  mLines, mInline: TArray<string>;
  mIndex, mFirst, mIndent, mRoot: Integer;
  mPad: string;
begin
  mFirst := ADfm.Nodes[ASplit.Removed[0]].First;
  mIndent := ADfm.Nodes[ASplit.Removed[0]].Indent;
  mPad := StringOfChar(' ', mIndent + cFrameIndent);
  mInline := [Format(cInlineHead, [StringOfChar(' ', mIndent), AOptions.InstanceName, AOptions.FrameClass]),
    Format(cPropLine, [mPad, 'Left', IntToStr(ASplit.Bounds.Left)]),
    Format(cPropLine, [mPad, 'Top', IntToStr(ASplit.Bounds.Top)]),
    Format(cPropLine, [mPad, 'Width', IntToStr(ASplit.Bounds.Width)]),
    Format(cPropLine, [mPad, 'Height', IntToStr(ASplit.Bounds.Height)])];
  if ASplit.Align <> '' then
  begin
    mInline := mInline + [Format(cPropLine, [mPad, 'Align', ASplit.Align])];
  end;
  if ASplit.Anchors <> '' then
  begin
    mInline := mInline + [Format(cPropLine, [mPad, 'Anchors', ASplit.Anchors])];
  end;
  for mRoot in ASplit.Roots do
  begin
    mInline := mInline + InheritedLines(ADfm, ASplit, mRoot, mIndent + cFrameIndent, AKept);
  end;
  mInline := mInline + [StringOfChar(' ', mIndent) + 'end'];
  mLines := nil;
  for mIndex := 0 to High(ADfm.Lines) do
  begin
    if mIndex = mFirst then
    begin
      mLines := mLines + mInline;
    end
    else if not InRemoved(ADfm, ASplit, mIndex) then
    begin
      mLines := mLines + [ADfm.Lines[mIndex]];
    end;
  end;
  Result := string.Join(cCrLf, mLines);
end;

{ Handler }

type
  THandlerSplit = record
    Moved: TArray<string>;
    Kept: TArray<string>;
    Notes: TArray<string>;
  end;

/// <summary>Handler der Ereignisse in den Knoten des Frames (AInside) und außerhalb (AOutside).</summary>
procedure HandlersOf(const ADfm: TDfm; const ASplit: TSplit; out AInside, AOutside: TArray<string>);
var
  mIndex: Integer;
  mHandler: string;
begin
  AInside := nil;
  AOutside := nil;
  for mIndex := 0 to High(ADfm.Lines) do
  begin
    mHandler := EventHandler(ADfm.Lines[mIndex]);
    if mHandler = '' then
    begin
      Continue;
    end;
    if InRoots(ADfm, ASplit, mIndex) then
    begin
      if not Contains(AInside, mHandler) then
      begin
        AInside := AInside + [mHandler];
      end;
    end
    else if not Contains(AOutside, mHandler) then
    begin
      AOutside := AOutside + [mHandler];
    end;
  end;
end;

function SortHandlers(const ADfm: TDfm; const ASplit: TSplit; const AUnit: TAtlasFormUnit;
  AMoveHandlers: Boolean): THandlerSplit;
var
  mHandler, mCode: string;
  mInside, mOutside: TArray<string>;
begin
  Result := Default(THandlerSplit);
  HandlersOf(ADfm, ASplit, mInside, mOutside);
  mCode := string.Join(cCrLf, Copy(AUnit.Lines, AUnit.ImplementationLine, MaxInt));
  for mHandler in mInside do
  begin
    // Aufrufe im Code: der Kopf „procedure TForm.X(“ selbst zählt einmal.
    if AMoveHandlers and not Contains(mOutside, mHandler) and
      (Length(TAtlasNameSuggest.Places(mCode, mHandler)) <= 1) then
    begin
      Result.Moved := Result.Moved + [mHandler];
    end
    else
    begin
      Result.Kept := Result.Kept + [mHandler];
      Result.Notes := Result.Notes + [TAtlasExtractNote.cKept + '|' + mHandler];
    end;
  end;
end;

{ TAtlasExtractFrame }

class function TAtlasExtractFrame.Suggest(const AName: string; out AFrameClass, AFrameUnit,
  AInstance: string): Boolean;
var
  mWord: string;
  mIndex: Integer;
begin
  // Präfix aus Kleinbuchstaben weglassen: pnlAdresse → Adresse.
  mIndex := 1;
  while (mIndex <= Length(AName)) and CharInSet(AName[mIndex], ['a'..'z']) do
  begin
    Inc(mIndex);
  end;
  mWord := Copy(AName, mIndex, MaxInt);
  if mWord = '' then
  begin
    mWord := AName;
  end;
  mWord := UpperCase(Copy(mWord, 1, 1)) + Copy(mWord, 2, MaxInt);
  AFrameClass := 'Tfrm' + mWord;
  AFrameUnit := 'u' + mWord + 'Frame';
  AInstance := 'frm' + mWord;
  Result := IsValidIdent(AFrameClass);
end;

function CheckNames(const AOptions: TAtlasExtractOptions): string;
begin
  Result := '';
  if not IsValidIdent(AOptions.FrameClass) or not IsValidIdent(AOptions.FrameUnit, True) then
  begin
    Result := TAtlasExtractNote.cErrClass;
  end
  else if not IsValidIdent(AOptions.InstanceName) then
  begin
    Result := TAtlasExtractNote.cErrName;
  end;
end;

type
  TUnitParts = record
    FormUnit: TAtlasFormUnit;
    Fields: TArray<string>;
    Decls: TArray<string>;
    Bodies: TArray<string>;
  end;

/// <summary>Rümpfe der Handler AHandlers aus AUnit nehmen; Klassenname im Kopf als „%s.“.</summary>
function TakeBodies(var AUnit: TAtlasFormUnit; const AFormClass: string;
  const AHandlers: TArray<string>): TArray<string>;
var
  mHandler: string;
  mBodyFirst, mBodyLast: Integer;
  mLines: TArray<string>;
begin
  Result := nil;
  for mHandler in AHandlers do
  begin
    if not AUnit.FindBody(AFormClass, mHandler, mBodyFirst, mBodyLast) then
    begin
      Continue;
    end;
    mLines := Copy(AUnit.Lines, mBodyFirst, mBodyLast - mBodyFirst + 1);
    mLines[0] := mLines[0].Replace(AFormClass + '.', '%s.');
    Result := Result + mLines + [''];
    Delete(AUnit.Lines, mBodyFirst, mBodyLast - mBodyFirst + 1);
    // Doppelte Leerzeile zusammenziehen.
    if (mBodyFirst < Length(AUnit.Lines)) and (mBodyFirst > 0) and (AUnit.Lines[mBodyFirst].Trim = '') and
      (AUnit.Lines[mBodyFirst - 1].Trim = '') then
    begin
      Delete(AUnit.Lines, mBodyFirst, 1);
    end;
  end;
end;

function UnitParts(const AUnit: TAtlasFormUnit; const AFormClass: string;
  const AMoved, AHandlers: TArray<string>): TUnitParts;
var
  mFirst, mLast, mIndex, mInsert: Integer;
  mIsMethod: Boolean;
  mName: string;
begin
  Result := Default(TUnitParts);
  Result.FormUnit := AUnit;
  // Rümpfe zuerst (hinten), damit die Zeilen der Klasse gleich bleiben.
  Result.Bodies := TakeBodies(Result.FormUnit, AFormClass, AHandlers);
  if not Result.FormUnit.FindClass(AFormClass, mFirst, mLast) then
  begin
    Exit;
  end;
  mInsert := mFirst + 1;
  for mIndex := mLast - 1 downto mFirst + 1 do
  begin
    mName := TAtlasFormUnit.MemberName(Result.FormUnit.Lines[mIndex], mIsMethod);
    if (mName <> '') and not mIsMethod and Contains(AMoved, mName) then
    begin
      Result.Fields := [Result.FormUnit.Lines[mIndex]] + Result.Fields;
      Delete(Result.FormUnit.Lines, mIndex, 1);
      mInsert := mIndex;
    end
    else if (mName <> '') and mIsMethod and Contains(AHandlers, mName) then
    begin
      Result.Decls := [Result.FormUnit.Lines[mIndex]] + Result.Decls;
      Delete(Result.FormUnit.Lines, mIndex, 1);
    end;
  end;
  Insert('%s', Result.FormUnit.Lines, mInsert);
end;

/// <summary>Namen der Knoten, die im Formular bleiben (nicht verschoben, nicht im entfernten Knoten).</summary>
function RemainingNames(const ADfm: TDfm; const ASplit: TSplit; const AMoved: TArray<string>): TArray<string>;
var
  mNode: Integer;
begin
  Result := nil;
  for mNode := 1 to High(ADfm.Nodes) do
  begin
    if not Contains(AMoved, ADfm.Nodes[mNode].Name) and not ADfm.IsInside(mNode, ASplit.Removed[0]) then
    begin
      Result := Result + [ADfm.Nodes[mNode].Name];
    end;
  end;
end;

/// <summary>Platzhalter „%s“ in der Klasse durch das Feld des Frames ersetzen.</summary>
procedure PlaceInstance(var AUnit: TAtlasFormUnit; const AOptions: TAtlasExtractOptions);
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(AUnit.Lines) do
  begin
    if AUnit.Lines[mIndex] = '%s' then
    begin
      AUnit.Lines[mIndex] := '    ' + AOptions.InstanceName + ': ' + AOptions.FrameClass + ';';
    end;
  end;
end;

function WithoutNames(const AFields, ANames: TArray<string>): TArray<string>;
var
  mField: string;
  mIsMethod: Boolean;
begin
  Result := nil;
  for mField in AFields do
  begin
    if not Contains(ANames, TAtlasFormUnit.MemberName(mField, mIsMethod)) then
    begin
      Result := Result + [mField];
    end;
  end;
end;

class function TAtlasExtractFrame.Run(const AFormDfm, AFormUnit, AFormClass: string;
  const AOptions: TAtlasExtractOptions): TAtlasExtractResult;
var
  mDfm: TDfm;
  mSplit: TSplit;
  mHandlers: THandlerSplit;
  mParts: TUnitParts;
  mContainer: TArray<string>;
  mIndex: Integer;
  mName: string;
begin
  Result := Default(TAtlasExtractResult);
  Result.Error := CheckNames(AOptions);
  mDfm := ParseDfm(AFormDfm);
  if Result.Error = '' then
  begin
    Result.Error := SplitOf(mDfm, AOptions, mSplit);
  end;
  if Result.Error <> '' then
  begin
    Exit;
  end;
  Result.Moved := MovedNames(mDfm, mSplit);
  mHandlers := SortHandlers(mDfm, mSplit, TAtlasFormUnit.Create(AFormUnit), AOptions.MoveHandlers);
  Result.MovedHandlers := mHandlers.Moved;
  Result.KeptHandlers := mHandlers.Kept;
  Result.Notes := mHandlers.Notes;
  // Container selbst entfällt im Formular samt Feld, gehört aber nicht in den Frame.
  mContainer := nil;
  if AOptions.ContainerAsFrame then
  begin
    mContainer := [mDfm.Nodes[mSplit.Removed[0]].Name];
    Result.Notes := Result.Notes + [TAtlasExtractNote.cContainerProps + '|' + mContainer[0]];
  end;
  Result.FrameDfm := FrameDfmText(mDfm, mSplit, AOptions, Result.KeptHandlers);
  Result.FormDfm := FormDfmText(mDfm, mSplit, AOptions, Result.KeptHandlers);
  mParts := UnitParts(TAtlasFormUnit.Create(AFormUnit), AFormClass, Result.Moved + mContainer,
    Result.MovedHandlers);
  PlaceInstance(mParts.FormUnit, AOptions);
  for mName in Result.Moved do
  begin
    Prefix(mParts.FormUnit, mParts.FormUnit.ImplementationLine, mName, AOptions.InstanceName);
  end;
  // Probleme: mitwandernde Handler, die Felder des Formulars nutzen.
  for mName in UsedFields(string.Join(cCrLf, mParts.Bodies), RemainingNames(mDfm, mSplit, Result.Moved)) do
  begin
    Result.Notes := Result.Notes + [TAtlasExtractNote.cFormField + '|' + mName];
  end;
  for mIndex := 0 to High(mParts.Bodies) do
  begin
    mParts.Bodies[mIndex] := mParts.Bodies[mIndex].Replace('%s.', AOptions.FrameClass + '.');
  end;
  Result.FrameUnit := FrameUnitText(AOptions, UsesLines(mParts.FormUnit), WithoutNames(mParts.Fields, mContainer),
    mParts.Decls, mParts.Bodies);
  Result.FormUnit := AddToUses(mParts.FormUnit, AOptions.FrameUnit).Text;
end;

end.
