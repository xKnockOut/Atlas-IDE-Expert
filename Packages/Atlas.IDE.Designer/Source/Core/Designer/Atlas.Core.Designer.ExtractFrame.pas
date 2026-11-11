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

function ParseDfm(const AText: string): TDfm;
var
  mStack: TArray<Integer>;
  mIndex: Integer;
  mNode: TNode;
  mName, mClass: string;
  mTop: Integer;
begin
  Result.Lines := AText.Replace(cCrLf, #10).Split([#10]);
  Result.Nodes := nil;
  mStack := nil;
  for mIndex := 0 to High(Result.Lines) do
  begin
    if HeaderOf(Result.Lines[mIndex], mName, mClass) then
    begin
      if Length(mStack) > 0 then
      begin
        mTop := mStack[High(mStack)];
        if Result.Nodes[mTop].PropsLast < 0 then
        begin
          Result.Nodes[mTop].PropsLast := mIndex - 1;
        end;
      end;
      mNode := Default(TNode);
      mNode.Name := mName;
      mNode.ClassName := mClass;
      mNode.Indent := TAtlasFormUnit.SpacesOf(Result.Lines[mIndex]);
      mNode.First := mIndex;
      mNode.Last := -1;
      mNode.PropsLast := -1;
      mNode.Parent := -1;
      if Length(mStack) > 0 then
      begin
        mNode.Parent := mStack[High(mStack)];
      end;
      Result.Nodes := Result.Nodes + [mNode];
      mStack := mStack + [High(Result.Nodes)];
    end
    else if (Length(mStack) > 0) and (Result.Lines[mIndex].Trim = 'end') and
      (TAtlasFormUnit.SpacesOf(Result.Lines[mIndex]) = Result.Nodes[mStack[High(mStack)]].Indent) then
    begin
      mTop := mStack[High(mStack)];
      Result.Nodes[mTop].Last := mIndex;
      if Result.Nodes[mTop].PropsLast < 0 then
      begin
        Result.Nodes[mTop].PropsLast := mIndex - 1;
      end;
      SetLength(mStack, Length(mStack) - 1);
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
    if (TAtlasFormUnit.SpacesOf(mLine) = Nodes[ANode].Indent + cFrameIndent) and StartsText(AProp + ' = ', mLine.Trim) then
    begin
      AValue := Copy(mLine.Trim, Length(AProp) + 4, MaxInt);
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
  mEq := Pos(' = ', mText);
  if StartsText('On', mText) and (mEq > 0) and IsValidIdent(Copy(mText, mEq + 3, MaxInt)) then
  begin
    Result := Copy(mText, mEq + 3, MaxInt);
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

function SplitOf(const ADfm: TDfm; const AOptions: TAtlasExtractOptions; out ASplit: TSplit): string;
var
  mName: string;
  mNode, mParent, mChild: Integer;
  mRect: TRect;
begin
  Result := '';
  ASplit := Default(TSplit);
  if Length(AOptions.Names) = 0 then
  begin
    Exit(TAtlasExtractNote.cErrNothing);
  end;
  mParent := -2;
  for mName in AOptions.Names do
  begin
    mNode := ADfm.IndexOf(mName);
    if mNode <= 0 then
    begin
      Exit(TAtlasExtractNote.cErrNotFound + '|' + mName);
    end;
    if (mParent <> -2) and (ADfm.Nodes[mNode].Parent <> mParent) then
    begin
      Exit(TAtlasExtractNote.cErrParents);
    end;
    mParent := ADfm.Nodes[mNode].Parent;
    ASplit.Removed := ASplit.Removed + [mNode];
    mRect := Bounds(IntValue(ADfm, mNode, 'Left'), IntValue(ADfm, mNode, 'Top'), IntValue(ADfm, mNode, 'Width'),
      IntValue(ADfm, mNode, 'Height'));
    if Length(ASplit.Removed) = 1 then
    begin
      ASplit.Bounds := mRect;
    end
    else
    begin
      ASplit.Bounds.Union(mRect);
    end;
  end;
  if Length(ASplit.Removed) = 1 then
  begin
    ADfm.Value(ASplit.Removed[0], 'Align', ASplit.Align);
    ADfm.Value(ASplit.Removed[0], 'Anchors', ASplit.Anchors);
  end;
  if AOptions.ContainerAsFrame and (Length(ASplit.Removed) = 1) then
  begin
    for mChild := 0 to High(ADfm.Nodes) do
    begin
      if ADfm.Nodes[mChild].Parent = ASplit.Removed[0] then
      begin
        ASplit.Roots := ASplit.Roots + [mChild];
      end;
    end;
  end
  else
  begin
    ASplit.Roots := ASplit.Removed;
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
  mLines := ['unit ' + AOptions.FrameUnit + ';', '', 'interface', '', 'uses'] + mUses +
    ['', 'type', '  ' + AOptions.FrameClass + ' = class(TFrame)'];
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
    AResult := StringOfChar(' ', TAtlasFormUnit.SpacesOf(ALine)) + AProp + ' = ' +
      IntToStr(StrToIntDef(Copy(mText, Length(AProp) + 4, MaxInt), 0) - ADelta);
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
  mLines := ['object ' + AOptions.InstanceName + ': ' + AOptions.FrameClass, '  Left = 0', '  Top = 0',
    '  Width = ' + IntToStr(ASplit.Bounds.Width), '  Height = ' + IntToStr(ASplit.Bounds.Height), '  TabOrder = 0'];
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
    Result := [StringOfChar(' ', AIndent) + 'inherited ' + ADfm.Nodes[ANode].Name + ': ' +
      ADfm.Nodes[ANode].ClassName] + mOwn + mInner + [StringOfChar(' ', AIndent) + 'end'];
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
  mInline := [StringOfChar(' ', mIndent) + 'inline ' + AOptions.InstanceName + ': ' + AOptions.FrameClass,
    mPad + 'Left = ' + IntToStr(ASplit.Bounds.Left), mPad + 'Top = ' + IntToStr(ASplit.Bounds.Top),
    mPad + 'Width = ' + IntToStr(ASplit.Bounds.Width), mPad + 'Height = ' + IntToStr(ASplit.Bounds.Height)];
  if ASplit.Align <> '' then
  begin
    mInline := mInline + [mPad + 'Align = ' + ASplit.Align];
  end;
  if ASplit.Anchors <> '' then
  begin
    mInline := mInline + [mPad + 'Anchors = ' + ASplit.Anchors];
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

procedure SortHandlers(const ADfm: TDfm; const ASplit: TSplit; const AUnit: TAtlasFormUnit;
  const AOptions: TAtlasExtractOptions; out AMoved, AKept: TArray<string>; var ANotes: TArray<string>);
var
  mIndex: Integer;
  mHandler: string;
  mInside, mOutside: TArray<string>;
  mCode: string;
begin
  mInside := nil;
  mOutside := nil;
  for mIndex := 0 to High(ADfm.Lines) do
  begin
    mHandler := EventHandler(ADfm.Lines[mIndex]);
    if mHandler = '' then
    begin
      Continue;
    end;
    if InRoots(ADfm, ASplit, mIndex) then
    begin
      if not Contains(mInside, mHandler) then
      begin
        mInside := mInside + [mHandler];
      end;
    end
    else if not Contains(mOutside, mHandler) then
    begin
      mOutside := mOutside + [mHandler];
    end;
  end;
  mCode := string.Join(cCrLf, Copy(AUnit.Lines, AUnit.ImplementationLine, MaxInt));
  AMoved := nil;
  AKept := nil;
  for mHandler in mInside do
  begin
    // Aufrufe im Code: der Kopf „procedure TForm.X(“ selbst zählt einmal.
    if AOptions.MoveHandlers and not Contains(mOutside, mHandler) and
      (Length(TAtlasNameSuggest.Places(mCode, mHandler)) <= 1) then
    begin
      AMoved := AMoved + [mHandler];
    end
    else
    begin
      AKept := AKept + [mHandler];
      ANotes := ANotes + [TAtlasExtractNote.cKept + '|' + mHandler];
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

function UnitParts(const AUnit: TAtlasFormUnit; const AFormClass: string; const AMoved, AHandlers: TArray<string>;
  out AFields, ADecls, ABodies: TArray<string>): TAtlasFormUnit;
var
  mFirst, mLast, mIndex, mInsert, mBodyFirst, mBodyLast: Integer;
  mIsMethod: Boolean;
  mName, mHandler: string;
  mLines: TArray<string>;
begin
  AFields := nil;
  ADecls := nil;
  ABodies := nil;
  Result := AUnit;
  // Rümpfe zuerst (hinten), damit die Zeilen der Klasse gleich bleiben.
  for mHandler in AHandlers do
  begin
    if Result.FindBody(AFormClass, mHandler, mBodyFirst, mBodyLast) then
    begin
      mLines := Copy(Result.Lines, mBodyFirst, mBodyLast - mBodyFirst + 1);
      mLines[0] := mLines[0].Replace(AFormClass + '.', '%s.');
      ABodies := ABodies + mLines + [''];
      Delete(Result.Lines, mBodyFirst, mBodyLast - mBodyFirst + 1);
      // Doppelte Leerzeile zusammenziehen.
      if (mBodyFirst < Length(Result.Lines)) and (mBodyFirst > 0) and (Result.Lines[mBodyFirst].Trim = '') and
        (Result.Lines[mBodyFirst - 1].Trim = '') then
      begin
        Delete(Result.Lines, mBodyFirst, 1);
      end;
    end;
  end;
  if not Result.FindClass(AFormClass, mFirst, mLast) then
  begin
    Exit;
  end;
  mInsert := -1;
  for mIndex := mLast - 1 downto mFirst + 1 do
  begin
    mName := TAtlasFormUnit.MemberName(Result.Lines[mIndex], mIsMethod);
    if (mName <> '') and not mIsMethod and Contains(AMoved, mName) then
    begin
      AFields := [Result.Lines[mIndex]] + AFields;
      Delete(Result.Lines, mIndex, 1);
      mInsert := mIndex;
    end
    else if (mName <> '') and mIsMethod and Contains(AHandlers, mName) then
    begin
      ADecls := [Result.Lines[mIndex]] + ADecls;
      Delete(Result.Lines, mIndex, 1);
    end;
  end;
  if mInsert < 0 then
  begin
    mInsert := mFirst + 1;
  end;
  Insert('%s', Result.Lines, mInsert);
end;

class function TAtlasExtractFrame.Run(const AFormDfm, AFormUnit, AFormClass: string;
  const AOptions: TAtlasExtractOptions): TAtlasExtractResult;
var
  mDfm: TDfm;
  mSplit: TSplit;
  mUnit: TAtlasFormUnit;
  mFields, mDecls, mBodies, mRemaining, mUsed, mContainer: TArray<string>;
  mIndex: Integer;
  mIsMethod: Boolean;
  mName, mBody, mField: string;
  mNode: Integer;
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
  mUnit := TAtlasFormUnit.Create(AFormUnit);
  SortHandlers(mDfm, mSplit, mUnit, AOptions, Result.MovedHandlers, Result.KeptHandlers, Result.Notes);
  if AOptions.ContainerAsFrame then
  begin
    Result.Notes := Result.Notes + [TAtlasExtractNote.cContainerProps + '|' + mDfm.Nodes[mSplit.Removed[0]].Name];
  end;
  Result.FrameDfm := FrameDfmText(mDfm, mSplit, AOptions, Result.KeptHandlers);
  Result.FormDfm := FormDfmText(mDfm, mSplit, AOptions, Result.KeptHandlers);
  // Container selbst entfällt im Formular samt Feld, gehört aber nicht in den Frame.
  mContainer := nil;
  if AOptions.ContainerAsFrame then
  begin
    mContainer := [mDfm.Nodes[mSplit.Removed[0]].Name];
  end;
  mUnit := UnitParts(mUnit, AFormClass, Result.Moved + mContainer, Result.MovedHandlers, mFields, mDecls, mBodies);
  for mIndex := 0 to High(mUnit.Lines) do
  begin
    if mUnit.Lines[mIndex] = '%s' then
    begin
      mUnit.Lines[mIndex] := '    ' + AOptions.InstanceName + ': ' + AOptions.FrameClass + ';';
    end;
  end;
  for mIndex := High(mFields) downto 0 do
  begin
    if Contains(mContainer, TAtlasFormUnit.MemberName(mFields[mIndex], mIsMethod)) then
    begin
      Delete(mFields, mIndex, 1);
    end;
  end;
  for mName in Result.Moved do
  begin
    Prefix(mUnit, mUnit.ImplementationLine, mName, AOptions.InstanceName);
  end;
  // Probleme: mitwandernde Handler, die Felder des Formulars nutzen.
  mRemaining := nil;
  for mNode := 1 to High(mDfm.Nodes) do
  begin
    if not Contains(Result.Moved, mDfm.Nodes[mNode].Name) and not mDfm.IsInside(mNode, mSplit.Removed[0]) then
    begin
      mRemaining := mRemaining + [mDfm.Nodes[mNode].Name];
    end;
  end;
  mBody := string.Join(cCrLf, mBodies);
  mUsed := UsedFields(mBody, mRemaining);
  for mField in mUsed do
  begin
    Result.Notes := Result.Notes + [TAtlasExtractNote.cFormField + '|' + mField];
  end;
  for mIndex := 0 to High(mBodies) do
  begin
    mBodies[mIndex] := mBodies[mIndex].Replace('%s.', AOptions.FrameClass + '.');
  end;
  Result.FrameUnit := FrameUnitText(AOptions, UsesLines(mUnit), mFields, mDecls, mBodies);
  Result.FormUnit := AddToUses(mUnit, AOptions.FrameUnit).Text;
end;

end.
