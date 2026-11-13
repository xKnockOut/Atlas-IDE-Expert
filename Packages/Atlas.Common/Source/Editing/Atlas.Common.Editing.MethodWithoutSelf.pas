unit Atlas.Common.Editing.MethodWithoutSelf;

// Methode ohne Self umwandeln (#686):
//   Erkennung: eine Instanzmethode einer Klasse oder eines Records, deren
//     Rumpf in der Unit steht und die weder Self noch ein Instanzmitglied
//     (Feld, Property, Instanzmethode, Konstruktor, auch ohne Self. davor)
//     noch inherited oder with benutzt. Nicht virtual, dynamic, override,
//     abstract, message, reintroduce oder final, nicht überladen, kein
//     Konstruktor, Destruktor oder Operator, keine Zugriffsmethode einer
//     Property, nicht Teil eines Interfaces der Klasse (Vorfahrenliste oder
//     Methodenzuordnung), nicht in der Formulardatei als Ereignis und in den
//     Methoden der Datei (auch abgeleiteter Klassen) nicht als Methodenzeiger
//     benutzt. Ob Namen
//     Instanzmitglieder sind, sagt TMethodLookup (Namensauflösung, sonst die
//     Klasse in der Datei); unbekannte Namen verhindern die Erkennung.
//   In class-Methode umwandeln: class davor, mit refactoring.methodKindStatic
//     auch static (Records immer). Braucht der Rumpf Klassenmethoden ohne
//     static, bleibt static weg (Warnung). Aufrufe über Instanzen bleiben
//     gültig; die zweite Aktion stellt Aufrufe über eine Variablenkette
//     (K.X, Liste[I].X) auf die Klasse um.
//   In freie Routine umwandeln: Deklaration aus der Klasse entfernen, Kopf
//     ohne Klasse; ins interface, wenn die Klasse dort steht und andere Units
//     die Methode aufrufen, sonst nur in implementation (vor die erste
//     Routine der Unit, die sie aufruft). Klassenmitglieder im Rumpf (class
//     var, Konstanten, Typen, class-Methoden) bekommen die Klasse davor;
//     strict private bzw. strict protected verhindern das. Aufrufe verlieren
//     den Objektbezug (Warnung, wenn der weggefallene Ausdruck mehr als eine
//     Variablenkette war), andere Units bekommen die Unit ins uses (#284) und
//     rufen sie qualifiziert auf, wenn sie selbst einen gleichnamigen Namen
//     deklarieren.
//   In Record-Helper verschieben: wenn der erste Parameter einen einfachen
//     Typ hat (string, Integer, TDateTime …), nicht var/out, ohne Vorgabewert
//     und im Rumpf nicht geschrieben wird. Die Methode wandert in einen
//     vorhandenen record helper der Unit für den Typ oder einen neuen
//     T<Typ>Helper (im interface nur, wenn andere Units aufrufen), der
//     Parameter wird Self, Aufrufe werden S.X(Rest) bzw. (Ausdruck).X(Rest).
//     Ist für den Typ schon ein anderer Helper sichtbar, warnt Atlas: Nur ein
//     Helper je Typ wirkt.
// Die Verwendungen in allen Dateien liefert der Aufrufer (Referenzsuche);
// jede Datei muss danach fehlerfrei parsen.

interface

uses
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Editing.MethodWithoutSelf.Lookup,
  Atlas.Common.Editing.MethodWithoutSelf.Contract;

type
  TMethodWithoutSelf = class
  public const
    /// <summary>Text der Marke für Clients; das Plugin beschriftet sie selbst in der Sprache der IDE.</summary>
    cMarkerText = 'Self unused';
  public
    class function ClassMethodTitle: string; static;
    class function ClassMethodCallsTitle: string; static;
    class function RoutineTitle: string; static;
    class function HelperTitle: string; static;
    /// <summary>Methode ohne Self, deren Kopf (Implementierung oder Deklaration) APosition enthält.</summary>
    class function Target(const AText: string; ATree: TSyntaxTree; const APosition: TTextPosition;
      const ALookup: TMethodLookup; out ATarget: TMethodTarget; out AReason: string): Boolean; static;
    /// <summary>Alle Methoden ohne Self der Datei (Marke, Hinweis).</summary>
    class function Candidates(const AText: string; ATree: TSyntaxTree;
      const ALookup: TMethodLookup): TArray<TMethodTarget>; static;
    /// <summary>Verwendung des Namens AName, der an AOffset beginnt; ACall: der Aufruf mit Argumenten oder nil.
    /// </summary>
    class function UseAt(ATree: TSyntaxTree; AOffset: Integer; const AName: string; out ACallee,
      ACall: TSyntaxNode): TMethodUse; static;
    /// <summary>Wandelt die Methode in ADeclaring um, wie ARequest sagt; AOthers: weitere Dateien mit
    /// Verwendungen.</summary>
    class function Execute(const ADeclaring: TMethodSource; const AOthers: TArray<TMethodSource>;
      const ARequest: TMethodRequest; out AResult: TMethodResult; out AReason: string): Boolean; static;
    /// <summary>Name der Umwandlung für Befehlsargumente: classMethod, classMethodCalls, routine, helper.</summary>
    class function ConversionName(AConversion: TMethodConversion): string; static;
    class function ConversionOf(const AName: string; out AConversion: TMethodConversion): Boolean; static;
    /// <summary>Einfacher Typ für einen Record-Helper?</summary>
    class function IsSimpleType(const ATypeName: string): Boolean; static;
    /// <summary>Name eines neuen Helpers: TStringHelper, TDateTimeHelper.</summary>
    class function HelperNameFor(const ATypeName: string): string; static;
  end;

implementation

uses
  Atlas.Common.Pascal.TreeCache,
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Text.Lines,
  Atlas.Common.Index.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Editing.RoutineBody,
  Atlas.Common.Editing.RoutineParts,
  Atlas.Common.Editing.ChangeSignature,
  Atlas.Common.Editing.UsesActions,
  Atlas.Common.Editing.MethodWithoutSelf.Texts,
  Atlas.Common.Editing.MethodWithoutSelf.Analysis;

class function TMethodWithoutSelf.ClassMethodTitle: string;
begin
  Result := cTexts[TEditingMethodWithoutSelfText.ConvertToClassMethod].Text;
end;

class function TMethodWithoutSelf.ClassMethodCallsTitle: string;
begin
  Result := cTexts[TEditingMethodWithoutSelfText.ConvertToClassMethodCalls].Text;
end;

class function TMethodWithoutSelf.RoutineTitle: string;
begin
  Result := cTexts[TEditingMethodWithoutSelfText.ConvertToStandaloneRoutine].Text;
end;

class function TMethodWithoutSelf.HelperTitle: string;
begin
  Result := cTexts[TEditingMethodWithoutSelfText.MoveToRecordHelperFor].Text;
end;

const
  // Direktiven, die an einer freien Routine bzw. einem Helper nicht passen.
  cDroppedDirectives: array[0..8] of string = ('overload', 'reintroduce', 'final', 'static', 'virtual', 'dynamic',
    'override', 'abstract', 'message');

function Capitalized(const AName: string): string;
begin
  Result := AName;
  if Result <> '' then
  begin
    Result := UpperCase(Result[1]) + Copy(Result, 2, MaxInt);
  end;
end;

function SameTypeName(const A, B: string): Boolean;
begin
  Result := SameText(A, B) or (MatchText(A, ['string', 'UnicodeString']) and MatchText(B, ['string',
    'UnicodeString']));
end;

{ Umwandlung }

type
  /// <summary>Bearbeitungen einer Datei in Offsets.</summary>
  TFileWork = class
  public
    FileName: string;
    Text: string;
    Tree: TSyntaxTree;
    Lines: TLineTable;
    Edits: TArray<TOffsetEdit>;
    Offsets: TArray<Integer>;
    Declaring: Boolean;
    /// <summary>Unit des Aufrufers braucht die Unit der Methode im uses.</summary>
    NeedsUses: Boolean;
    /// <summary>Eigene Namen auf Unit-Ebene (gleichnamige Routine verdeckt die neue).</summary>
    Names: TArray<string>;
    constructor Create(const ASource: TMethodSource; ADeclaring: Boolean);
  end;

constructor TFileWork.Create(const ASource: TMethodSource; ADeclaring: Boolean);
begin
  inherited Create;
  FileName := ASource.FileName;
  Text := ASource.Text;
  Tree := ASource.Tree;
  Lines := TLineTable.Build(Text);
  Offsets := ASource.Offsets;
  Declaring := ADeclaring;
  if Tree <> nil then
  begin
    Names := TRoutineParts.UnitNames(Tree.Root);
  end;
end;

/// <summary>Bearbeitung, die ANode samt Zeile entfernt, wenn die Zeile sonst leer ist; sonst nur den Bereich.</summary>
function RemoveLine(const AText: string; const ALines: TLineTable; ANode: TSyntaxNode): TOffsetEdit;
var
  mLineStart, mNextStart: Integer;
begin
  mLineStart := ALines.LineStart(ANode.StartPos.Line);
  mNextStart := ALines.LineStart(ANode.EndPos.Line + 1);
  if ANode.EndPos.Line + 1 >= ALines.LineCount then
  begin
    mNextStart := Length(AText);
  end;
  if (Trim(Copy(AText, mLineStart + 1, ANode.StartOffset - mLineStart)) = '') and
    (Trim(Copy(AText, ANode.EndOffset + 1, mNextStart - ANode.EndOffset)) = '') then
  begin
    Result := TOffsetEdit.Create(mLineStart, mNextStart, '');
  end
  else
  begin
    Result := TOffsetEdit.Create(ANode.StartOffset, ANode.EndOffset, '');
  end;
end;

/// <summary>Direktiven der Deklaration, die mitkommen ("inline; stdcall;"), mit führendem Leerzeichen.</summary>
function KeptDirectives(const AText: string; ADeclaration: TSyntaxNode): string;
var
  mIndex: Integer;
  mChild: TSyntaxNode;
begin
  Result := '';
  for mIndex := 0 to ADeclaration.ChildCount - 1 do
  begin
    mChild := ADeclaration[mIndex];
    if (mChild.Kind = TSyntaxKind.Directive) and (IndexText(mChild.Name, cDroppedDirectives) < 0) then
    begin
      Result := Result + ' ' + TRoutineBody.TextOf(AText, mChild) + ';';
    end;
  end;
end;

/// <summary>Einrückung der Zeile ALine.</summary>
function IndentAt(const AText: string; const ALines: TLineTable; ALine: Integer): string;
begin
  Result := TTextLines.IndentOf(Copy(AText, ALines.LineStart(ALine) + 1, ALines.LineContentEnd(ALine) -
    ALines.LineStart(ALine)));
end;

/// <summary>Zeile ALine ohne Umbruch.</summary>
function LineText(const AText: string; const ALines: TLineTable; ALine: Integer): string;
begin
  Result := Copy(AText, ALines.LineStart(ALine) + 1, ALines.LineContentEnd(ALine) - ALines.LineStart(ALine));
end;

type
  TMethodBuild = class
  public
    Plan: TMethodPlan;
    Conversion: TMethodConversion;
    StaticWanted: Boolean;
    Style: TFormatStyle;
    LineBreak: string;
    Works: TObjectList<TFileWork>;
    Warnings: TArray<string>;
    PreviewLines: TArray<string>;
    Calls: Integer;
    /// <summary>Andere Units rufen auf: Deklaration im interface.</summary>
    CalledOutside: Boolean;
    /// <summary>Verwendungen in der Unit der Methode außerhalb ihres Rumpfs (Offsets).</summary>
    FirstUse: Integer;
    HelperName: string;
    HelperNode: TSyntaxNode;
    constructor Create(APlan: TMethodPlan);
    destructor Destroy; override;
    procedure Warn(const AText: string);
    /// <summary>Warnung: Der Ausdruck vor dem Namen wird nicht mehr ausgewertet.</summary>
    procedure WarnLost(AWork: TFileWork; ALine: Integer; AReceiver: TSyntaxNode);
    function AddSite(AWork: TFileWork; AOffset: Integer; out AReason: string): Boolean;
    procedure NoteUse(AWork: TFileWork; AOffset: Integer; ACallee: TSyntaxNode);
    function SiteEdit(AWork: TFileWork; AOffset, ALine: Integer; ACallee, ACall: TSyntaxNode;
      out AEdit: TOffsetEdit): Boolean;
    function RoutineCallEdit(AWork: TFileWork; AOffset, ALine: Integer; AReceiver: TSyntaxNode;
      out AEdit: TOffsetEdit): Boolean;
    function HelperCallEdit(AWork: TFileWork; ALine: Integer; AReceiver, ACall: TSyntaxNode;
      out AEdit: TOffsetEdit): Boolean;
    procedure RecordEdit(AWork: TFileWork; ALine: Integer; const AEdit: TOffsetEdit);
    function DeclaringEdits(out AReason: string): Boolean;
    procedure ClassMethodEdits;
    function RoutineEdits(out AReason: string): Boolean;
    function HelperEdits(out AReason: string): Boolean;
    function InsertIntoHelper(const ADecl, AInner: string): string;
    procedure AddHelperAfterClass(const ADecl, AInner: string);
    procedure AddHelperInImplementation(const ADecl, AInner: string);
    function QualifyStatics: TArray<TOffsetEdit>;
    function ChooseHelper(out AReason: string): Boolean;
    function ExistingHelperIssue(AFound: TSyntaxNode): string;
    function NewHelperIssue(const AVisible: string): string;
    function WorkIssue(AWork: TFileWork; out AItem: TMethodFileEdits): string;
    function Finish(out AResult: TMethodResult; out AReason: string): Boolean;
  end;

constructor TMethodBuild.Create(APlan: TMethodPlan);
begin
  inherited Create;
  Plan := APlan;
  Works := TObjectList<TFileWork>.Create(True);
  LineBreak := TTextLines.LineBreakOf(APlan.Text);
  FirstUse := MaxInt;
end;

destructor TMethodBuild.Destroy;
begin
  Works.Free;
  inherited;
end;

procedure TMethodBuild.Warn(const AText: string);
begin
  if IndexStr(AText, Warnings) < 0 then
  begin
    Warnings := Warnings + [AText];
  end;
end;

procedure TMethodBuild.WarnLost(AWork: TFileWork; ALine: Integer; AReceiver: TSyntaxNode);
begin
  Warn(cTexts[TEditingMethodWithoutSelfText.IsNoLongerEvaluated].Fmt([TMethodPlan.Where(AWork.FileName, ALine),
    TRoutineBody.TextOf(AWork.Text, AReceiver)]));
end;

/// <summary>Verwendungen, die sich nicht umstellen lassen; '' sonst.</summary>
function UseIssue(AUse: TMethodUse; AIsPointer: Boolean): string;
begin
  Result := '';
  if AIsPointer then
  begin
    Exit(cTexts[TEditingMethodWithoutSelfText.UsedAsAMethodPointer].Text);
  end;
  case AUse of
    TMethodUse.Inherited_:
      Result := cTexts[TEditingMethodWithoutSelfText.InheritedCall].Text;
    TMethodUse.Accessor:
      Result := cTexts[TEditingMethodWithoutSelfText.AccessorOfAProperty].Text;
    TMethodUse.Unknown:
      Result := cTexts[TEditingMethodWithoutSelfText.UseNotRecognized].Text;
    TMethodUse.Call, TMethodUse.Value, TMethodUse.Pointer: ;
  end;
end;

function IsSelfNode(ANode: TSyntaxNode): Boolean;
begin
  Result := (ANode.Kind = TSyntaxKind.Identifier) and SameText(ANode.Name, 'Self');
end;

/// <summary>Aufruf über eine Variablenkette auf die Klasse umstellen (K.X → TKunde.X).</summary>
function ClassCallEdit(AReceiver: TSyntaxNode; const AClassName: string; out AEdit: TOffsetEdit): Boolean;
begin
  Result := (AReceiver <> nil) and TRoutineBody.IsVariableChain(AReceiver) and not IsSelfNode(AReceiver);
  if Result then
  begin
    AEdit := TOffsetEdit.Create(AReceiver.StartOffset, AReceiver.EndOffset, AClassName);
  end;
end;

/// <summary>Aufruf des Helpers: S.X(Rest) bzw. (Ausdruck).X(Rest).</summary>
function HelperCallText(const AText: string; ACall: TSyntaxNode; const AName: string): string;
var
  mFirst: TSyntaxNode;
begin
  mFirst := ACall[1];
  Result := TRoutineBody.TextOf(AText, mFirst);
  if not TRoutineBody.IsVariableChain(mFirst) then
  begin
    Result := '(' + Result + ')';
  end;
  Result := Result + '.' + AName;
  if ACall.ChildCount > 2 then
  begin
    Result := Result + '(' + Copy(AText, ACall[2].StartOffset + 1, ACall[ACall.ChildCount - 1].EndOffset -
      ACall[2].StartOffset) + ')';
  end;
end;

function TMethodBuild.AddSite(AWork: TFileWork; AOffset: Integer; out AReason: string): Boolean;
var
  mCallee, mCall: TSyntaxNode;
  mUse: TMethodUse;
  mLine: Integer;
  mEdit: TOffsetEdit;
begin
  mLine := AWork.Lines.PositionAt(AOffset).Line;
  mUse := TMethodWithoutSelf.UseAt(AWork.Tree, AOffset, Plan.Target.Name, mCallee, mCall);
  AReason := UseIssue(mUse, Plan.IsPointer(mUse));
  if (AReason = '') and (Conversion = TMethodConversion.Helper) and ((mCall = nil) or (mCall.ChildCount < 2)) then
  begin
    AReason := cTexts[TEditingMethodWithoutSelfText.CallWithoutArguments].Text;
  end;
  if AReason <> '' then
  begin
    AReason := TMethodPlan.Where(AWork.FileName, mLine) + ': ' + AReason;
    Exit(False);
  end;
  NoteUse(AWork, AOffset, mCallee);
  if SiteEdit(AWork, AOffset, mLine, mCallee, mCall, mEdit) then
  begin
    RecordEdit(AWork, mLine, mEdit);
  end
  else if (Conversion in [TMethodConversion.Routine, TMethodConversion.Helper]) and not AWork.Declaring then
  begin
    AWork.NeedsUses := True;
  end;
  Result := True;
end;

procedure TMethodBuild.NoteUse(AWork: TFileWork; AOffset: Integer; ACallee: TSyntaxNode);
begin
  if AWork.Declaring and not TRoutineBody.Within(ACallee, Plan.Routine) and (AOffset < FirstUse) then
  begin
    FirstUse := AOffset;
  end;
  if not AWork.Declaring then
  begin
    CalledOutside := True;
  end;
end;

function TMethodBuild.SiteEdit(AWork: TFileWork; AOffset, ALine: Integer; ACallee, ACall: TSyntaxNode;
  out AEdit: TOffsetEdit): Boolean;
var
  mReceiver: TSyntaxNode;
begin
  AEdit := TOffsetEdit.Create(0, 0, '');
  mReceiver := nil;
  if ACallee.Kind = TSyntaxKind.MemberAccess then
  begin
    mReceiver := ACallee[0];
  end;
  case Conversion of
    TMethodConversion.ClassMethodCalls:
      Result := ClassCallEdit(mReceiver, Plan.Target.ClassName, AEdit);
    TMethodConversion.Routine:
      Result := RoutineCallEdit(AWork, AOffset, ALine, mReceiver, AEdit);
    TMethodConversion.Helper:
      Result := HelperCallEdit(AWork, ALine, mReceiver, ACall, AEdit);
  else
    Result := False;
  end;
end;

/// <summary>Aufruf ohne Objektbezug; qualifiziert, wenn die aufrufende Unit den Namen selbst deklariert.</summary>
function TMethodBuild.RoutineCallEdit(AWork: TFileWork; AOffset, ALine: Integer; AReceiver: TSyntaxNode;
  out AEdit: TOffsetEdit): Boolean;
var
  mPrefix: string;
begin
  mPrefix := '';
  if not AWork.Declaring and (IndexText(Plan.Target.Name, AWork.Names) >= 0) then
  begin
    mPrefix := Plan.UnitName + '.';
  end;
  if AReceiver <> nil then
  begin
    if not TRoutineBody.IsVariableChain(AReceiver) then
    begin
      WarnLost(AWork, ALine, AReceiver);
    end;
    AEdit := TOffsetEdit.Create(AReceiver.StartOffset, AOffset, mPrefix);
    Exit(True);
  end;
  Result := mPrefix <> '';
  if Result then
  begin
    AEdit := TOffsetEdit.Create(AOffset, AOffset, mPrefix);
  end;
end;

function TMethodBuild.HelperCallEdit(AWork: TFileWork; ALine: Integer; AReceiver, ACall: TSyntaxNode;
  out AEdit: TOffsetEdit): Boolean;
begin
  if (AReceiver <> nil) and not TRoutineBody.IsVariableChain(AReceiver) then
  begin
    WarnLost(AWork, ALine, AReceiver);
  end;
  AEdit := TOffsetEdit.Create(ACall.StartOffset, ACall.EndOffset, HelperCallText(AWork.Text, ACall,
    Plan.Target.Name));
  Result := True;
end;

/// <summary>Bearbeitung übernehmen, Aufruf zählen und, wenn sie in einer Zeile bleibt, in die Vorschau.</summary>
procedure TMethodBuild.RecordEdit(AWork: TFileWork; ALine: Integer; const AEdit: TOffsetEdit);
var
  mBefore, mAfter: string;
begin
  AWork.Edits := AWork.Edits + [AEdit];
  if not AWork.Declaring then
  begin
    AWork.NeedsUses := True;
  end;
  Inc(Calls);
  if AWork.Lines.PositionAt(AEdit.Start).Line = AWork.Lines.PositionAt(AEdit.Stop).Line then
  begin
    mBefore := LineText(AWork.Text, AWork.Lines, ALine);
    mAfter := TRoutineParts.ApplyEdits(mBefore, AWork.Lines.LineStart(ALine), [AEdit]);
    PreviewLines := PreviewLines + [Format('%s: %s → %s', [TMethodPlan.Where(AWork.FileName, ALine), Trim(mBefore),
      Trim(mAfter)])];
  end;
end;

function TMethodBuild.QualifyStatics: TArray<TOffsetEdit>;
var
  mNode: TSyntaxNode;
begin
  Result := nil;
  for mNode in Plan.Statics do
  begin
    Result := Result + [TOffsetEdit.Create(mNode.StartOffset, mNode.StartOffset, Plan.Target.ClassName + '.')];
  end;
end;

procedure TMethodBuild.ClassMethodEdits;
var
  mWork: TFileWork;
  mWithStatic: Boolean;
begin
  mWork := Works[0];
  mWithStatic := StaticWanted or Plan.Target.IsRecord;
  if mWithStatic and Plan.UsesClassLevel and not Plan.Target.IsRecord then
  begin
    mWithStatic := False;
    Warn(cTexts[TEditingMethodWithoutSelfText.StaysWithoutStaticTheBody].Fmt([Plan.Target.Name]));
  end;
  mWork.Edits := mWork.Edits + [TOffsetEdit.Create(Plan.Declaration.StartOffset, Plan.Declaration.StartOffset,
    'class '), TOffsetEdit.Create(Plan.Header.StartOffset, Plan.Header.StartOffset, 'class ')];
  if mWithStatic then
  begin
    mWork.Edits := mWork.Edits + [TOffsetEdit.Create(Plan.Declaration.EndOffset, Plan.Declaration.EndOffset,
      ' static;')];
  end;
end;

/// <summary>Bearbeitungen, die AInner (im Bereich AStart..AStop) in den verschobenen Text übernehmen; die übrigen
/// bleiben in AEdits.</summary>
function SplitEdits(var AEdits: TArray<TOffsetEdit>; AStart, AStop: Integer): TArray<TOffsetEdit>;
var
  mKept: TArray<TOffsetEdit>;
  mEdit: TOffsetEdit;
begin
  Result := nil;
  mKept := nil;
  for mEdit in AEdits do
  begin
    if (mEdit.Start >= AStart) and (mEdit.Stop <= AStop) then
    begin
      Result := Result + [mEdit];
    end
    else
    begin
      mKept := mKept + [mEdit];
    end;
  end;
  AEdits := mKept;
end;

/// <summary>Oberste Routine der Implementierung, die AOffset enthält; nil ohne.</summary>
function TopLevelAt(AImplementation: TSyntaxNode; AOffset: Integer): TSyntaxNode;
var
  mIndex: Integer;
begin
  Result := nil;
  for mIndex := 0 to AImplementation.ChildCount - 1 do
  begin
    if (AImplementation[mIndex].Kind = TSyntaxKind.RoutineDecl) and
      TRoutineParts.Encloses(AImplementation[mIndex], AOffset) then
    begin
      Exit(AImplementation[mIndex]);
    end;
  end;
end;

/// <summary>Bereich der Routine samt Kommentaren darüber bis zum Anfang der Folgezeile, dazu eine Leerzeile
/// dahinter.</summary>
procedure RoutineSpan(const AText: string; const ALines: TLineTable; ARoutine: TSyntaxNode; out AStart,
  AStop: Integer);
var
  mNext: Integer;
begin
  AStart := ALines.LineStart(TRoutineBody.RoutineInsertLine(AText, ARoutine));
  mNext := ARoutine.EndPos.Line + 1;
  AStop := ALines.LineStart(mNext);
  if mNext >= ALines.LineCount then
  begin
    AStop := Length(AText);
  end
  else if Trim(LineText(AText, ALines, mNext)) = '' then
  begin
    AStop := ALines.LineStart(mNext + 1);
  end;
end;

function TMethodBuild.RoutineEdits(out AReason: string): Boolean;
var
  mWork: TFileWork;
  mHead, mMoved: string;
  mImplementation_, mFirst: TSyntaxNode;
  mStart, mStop, mInsertAt, mLine: Integer;
  mInner: TArray<TOffsetEdit>;
begin
  mWork := Works[0];
  if CalledOutside and not Plan.ClassInInterface then
  begin
    Exit(TMethodPlan.Fail(cTexts[TEditingMethodWithoutSelfText.OtherUnitsCallItBut].Text, AReason));
  end;
  mHead := TRoutineParts.HeadText(Plan.Text, Plan.Declaration, Plan.Target.Name, Plan.Parameters, False);
  mWork.Edits := mWork.Edits + [RemoveLine(Plan.Text, Plan.Lines, Plan.Declaration)];
  if CalledOutside then
  begin
    // Vor implementation, mit Leerzeile.
    mLine := Plan.Routine.Parent.StartPos.Line;
    mWork.Edits := mWork.Edits + [TOffsetEdit.Create(Plan.Lines.LineStart(mLine), Plan.Lines.LineStart(mLine),
      mHead + KeptDirectives(Plan.Text, Plan.Declaration) + LineBreak + LineBreak)];
    mWork.Edits := mWork.Edits + [TOffsetEdit.Create(Plan.Header.StartOffset, Plan.Header.EndOffset, mHead)];
  end
  else
  begin
    mWork.Edits := mWork.Edits + [TOffsetEdit.Create(Plan.Header.StartOffset, Plan.Header.EndOffset,
      mHead + KeptDirectives(Plan.Text, Plan.Declaration))];
  end;
  mWork.Edits := mWork.Edits + QualifyStatics;
  // Ohne Deklaration im interface muss die Routine vor ihrer ersten Verwendung stehen.
  if not CalledOutside and (FirstUse < Plan.Routine.StartOffset) then
  begin
    mImplementation_ := Plan.Routine.Parent;
    mFirst := TopLevelAt(mImplementation_, FirstUse);
    if mFirst = nil then
    begin
      Exit(TMethodPlan.Fail(cTexts[TEditingMethodWithoutSelfText.FirstUseNotInA].Text, AReason));
    end;
    RoutineSpan(Plan.Text, Plan.Lines, Plan.Routine, mStart, mStop);
    mInner := SplitEdits(mWork.Edits, mStart, mStop);
    mMoved := TRoutineParts.ApplyEdits(Copy(Plan.Text, mStart + 1, mStop - mStart), mStart, mInner);
    if not EndsStr(LineBreak + LineBreak, mMoved) then
    begin
      mMoved := mMoved + LineBreak;
    end;
    mInsertAt := Plan.Lines.LineStart(TRoutineBody.RoutineInsertLine(Plan.Text, mFirst));
    mWork.Edits := mWork.Edits + [TOffsetEdit.Create(mStart, mStop, ''), TOffsetEdit.Create(mInsertAt, mInsertAt,
      mMoved)];
  end;
  Result := True;
end;

/// <summary>record helper der Unit für ATypeName; nil ohne.</summary>
function ExistingHelper(ATree: TSyntaxTree; const ATypeName: string): TSyntaxNode;
var
  mTypeName: string;
begin
  mTypeName := ATypeName;
  Result := ATree.Root.Search(
    function(ANode: TSyntaxNode): TSyntaxSearchStep
    begin
      Result := TSyntaxSearchStep.Descend;
      if (ANode.Kind = TSyntaxKind.HelperType) and SameText(ANode.Name, 'record') and (ANode.ChildCount > 0) and
        (ANode[0].Kind = TSyntaxKind.TypeReference) and
        SameTypeName(TMethodLookup.HeadName(ANode[0].Name), mTypeName) then
      begin
        Result := TSyntaxSearchStep.Found;
      end;
    end);
end;

function TMethodBuild.ExistingHelperIssue(AFound: TSyntaxNode): string;
var
  mInterface: TSyntaxNode;
begin
  Result := '';
  mInterface := Plan.Tree.Root.FindChild(TSyntaxKind.InterfaceSection);
  if CalledOutside and ((mInterface = nil) or not TRoutineBody.Within(AFound, mInterface)) then
  begin
    Exit(cTexts[TEditingMethodWithoutSelfText.TheHelperIsInThe].Fmt([AFound.Parent.Name]));
  end;
  HelperNode := AFound;
  HelperName := AFound.Parent.Name;
end;

function TMethodBuild.NewHelperIssue(const AVisible: string): string;
var
  mBase: string;
begin
  Result := '';
  if CalledOutside and not Plan.ClassInInterface then
  begin
    Exit(cTexts[TEditingMethodWithoutSelfText.OtherUnitsCallItBut].Text);
  end;
  mBase := TMethodWithoutSelf.HelperNameFor(Plan.Target.HelperType);
  // Den Namen eines sichtbaren Helpers (TStringHelper der RTL) nicht verdecken: THauptStringHelper.
  if SameText(mBase, AVisible) or (Assigned(Plan.Lookup.NameVisible) and Plan.Lookup.NameVisible(mBase,
    Plan.Routine.StartOffset)) then
  begin
    mBase := 'T' + Capitalized(Plan.UnitName.Substring(Plan.UnitName.LastIndexOf('.') + 1)) + Copy(mBase, 2,
      MaxInt);
  end;
  HelperName := TRoutineParts.FreeName(mBase, TRoutineParts.UnitNames(Plan.Tree.Root));
end;

function TMethodBuild.ChooseHelper(out AReason: string): Boolean;
var
  mFound: TSyntaxNode;
  mTypeName, mVisible: string;
begin
  mTypeName := Plan.Target.HelperType;
  mFound := ExistingHelper(Plan.Tree, mTypeName);
  mVisible := '';
  if Assigned(Plan.Lookup.VisibleHelper) then
  begin
    mVisible := Plan.Lookup.VisibleHelper(mTypeName, Plan.Routine.StartOffset);
  end;
  if mFound <> nil then
  begin
    AReason := ExistingHelperIssue(mFound);
  end
  else
  begin
    AReason := NewHelperIssue(mVisible);
  end;
  if AReason <> '' then
  begin
    Exit(False);
  end;
  if (mVisible <> '') and not SameText(mVisible, HelperName) then
  begin
    Warn(cTexts[TEditingMethodWithoutSelfText.IsAlreadyVisibleFor].Fmt([mTypeName, mVisible, HelperName, mVisible]));
  end;
  Result := True;
end;

/// <summary>Letztes end im Bereich von ANode; -1 ohne.</summary>
function LastEndToken(const ATokens: TArray<TPascalToken>; ANode: TSyntaxNode): Integer;
var
  mIndex: Integer;
begin
  Result := -1;
  mIndex := TRoutineBody.TokenAt(ATokens, ANode.StartOffset);
  while (mIndex <= High(ATokens)) and (ATokens[mIndex].Offset < ANode.EndOffset) do
  begin
    if ATokens[mIndex].IsKeyword('end') then
    begin
      Result := mIndex;
    end;
    Inc(mIndex);
  end;
end;

/// <summary>Deklaration vor das end des vorhandenen Helpers.</summary>
function TMethodBuild.InsertIntoHelper(const ADecl, AInner: string): string;
var
  mEndToken, mLine: Integer;
begin
  Result := '';
  mEndToken := LastEndToken(Plan.Tokens, HelperNode);
  if mEndToken < 0 then
  begin
    Exit(cTexts[TEditingMethodWithoutSelfText.EndOfTheHelperNot].Text);
  end;
  mLine := Plan.Tokens[mEndToken].StartPos.Line;
  if Trim(Copy(LineText(Plan.Text, Plan.Lines, mLine), 1, Plan.Tokens[mEndToken].StartPos.Character)) <> '' then
  begin
    Exit(cTexts[TEditingMethodWithoutSelfText.EndOfTheHelperIs].Text);
  end;
  Works[0].Edits := Works[0].Edits + [TOffsetEdit.Create(Plan.Lines.LineStart(mLine),
    Plan.Lines.LineStart(mLine), IndentAt(Plan.Text, Plan.Lines, mLine) + AInner + ADecl + LineBreak)];
end;

/// <summary>Neuer Helper hinter der Klasse, im selben type-Abschnitt.</summary>
procedure TMethodBuild.AddHelperAfterClass(const ADecl, AInner: string);
var
  mTypeDecl: TSyntaxNode;
  mIndent, mBlock: string;
  mAt: Integer;
begin
  mTypeDecl := Plan.TypeBody.Parent;
  mIndent := IndentAt(Plan.Text, Plan.Lines, mTypeDecl.StartPos.Line);
  mBlock := LineBreak + mIndent + HelperName + ' = record helper for ' + Plan.Target.HelperType + LineBreak +
    mIndent + AInner + ADecl + LineBreak + mIndent + 'end;' + LineBreak;
  mAt := Plan.Lines.LineStart(mTypeDecl.EndPos.Line + 1);
  if mTypeDecl.EndPos.Line + 1 >= Plan.Lines.LineCount then
  begin
    mAt := Length(Plan.Text);
  end;
  Works[0].Edits := Works[0].Edits + [TOffsetEdit.Create(mAt, mAt, mBlock)];
end;

/// <summary>Neuer Helper am Anfang von implementation, hinter dessen uses.</summary>
procedure TMethodBuild.AddHelperInImplementation(const ADecl, AInner: string);
var
  mImplementation, mClause: TSyntaxNode;
  mLine, mAt: Integer;
  mBlock: string;
begin
  mImplementation := Plan.Routine.Parent;
  mClause := mImplementation.FindChild(TSyntaxKind.UsesClause);
  mLine := mImplementation.StartPos.Line + 1;
  if mClause <> nil then
  begin
    mLine := mClause.EndPos.Line + 1;
  end;
  mBlock := LineBreak + 'type' + LineBreak + AInner + HelperName + ' = record helper for ' +
    Plan.Target.HelperType + LineBreak + AInner + AInner + ADecl + LineBreak + AInner + 'end;' + LineBreak;
  mAt := Plan.Lines.LineStart(mLine);
  Works[0].Edits := Works[0].Edits + [TOffsetEdit.Create(mAt, mAt, mBlock)];
end;

function TMethodBuild.HelperEdits(out AReason: string): Boolean;
var
  mWork: TFileWork;
  mRest: TArray<TParameterText>;
  mDecl, mInner: string;
  mNode: TSyntaxNode;
begin
  if not ChooseHelper(AReason) then
  begin
    Exit(False);
  end;
  mWork := Works[0];
  mRest := Copy(Plan.Parameters, 1, MaxInt);
  mDecl := TRoutineParts.HeadText(Plan.Text, Plan.Declaration, Plan.Target.Name, mRest, False) +
    KeptDirectives(Plan.Text, Plan.Declaration);
  mInner := TRoutineBody.IndentUnit(Style);
  mWork.Edits := mWork.Edits + [RemoveLine(Plan.Text, Plan.Lines, Plan.Declaration)];
  AReason := '';
  if HelperNode <> nil then
  begin
    AReason := InsertIntoHelper(mDecl, mInner);
  end
  else if CalledOutside then
  begin
    AddHelperAfterClass(mDecl, mInner);
  end
  else
  begin
    AddHelperInImplementation(mDecl, mInner);
  end;
  if AReason <> '' then
  begin
    Exit(False);
  end;
  mWork.Edits := mWork.Edits + [TOffsetEdit.Create(Plan.Header.StartOffset, Plan.Header.EndOffset,
    TRoutineParts.HeadText(Plan.Text, Plan.Declaration, HelperName + '.' + Plan.Target.Name, mRest, False))];
  mWork.Edits := mWork.Edits + QualifyStatics;
  for mNode in Plan.FirstParameterNodes do
  begin
    mWork.Edits := mWork.Edits + [TOffsetEdit.Create(mNode.StartOffset, mNode.EndOffset, 'Self')];
  end;
  Result := True;
end;

function TMethodBuild.DeclaringEdits(out AReason: string): Boolean;
begin
  case Conversion of
    TMethodConversion.Routine:
      Result := RoutineEdits(AReason);
    TMethodConversion.Helper:
      Result := HelperEdits(AReason);
  else
    // class-Methode gelingt immer.
    ClassMethodEdits;
    Result := True;
  end;
end;

/// <summary>Überschneiden sich zwei Bearbeitungen (gleiche Einfügestelle zählt nicht)?</summary>
function Overlapping(const AEdits: TArray<TOffsetEdit>): Boolean;
var
  mIndex, mOther: Integer;
begin
  for mIndex := 0 to High(AEdits) do
  begin
    for mOther := mIndex + 1 to High(AEdits) do
    begin
      if (AEdits[mIndex].Start < AEdits[mOther].Stop) and (AEdits[mOther].Start < AEdits[mIndex].Stop) then
      begin
        Exit(True);
      end;
    end;
  end;
  Result := False;
end;

/// <summary>Bearbeitungen einer Datei als Textänderungen, samt uses für die Unit AUnitName.</summary>
function TextEditsOf(AWork: TFileWork; const AUnitName: string): TMethodFileEdits;
var
  mEdit: TOffsetEdit;
  mUsesEdits: TArray<TTextEdit>;
  mAdded: TArray<string>;
begin
  Result.FileName := AWork.FileName;
  Result.Edits := nil;
  for mEdit in AWork.Edits do
  begin
    Result.Edits := Result.Edits + [TTextEdit.Create(TTextRange.Create(AWork.Lines.PositionAt(mEdit.Start),
      AWork.Lines.PositionAt(mEdit.Stop)), mEdit.Text)];
  end;
  if AWork.NeedsUses and TUsesActions.AddUnits(AWork.Tree.Tokens, TUsesAddRequest.Create(
    TArray<string>.Create(AUnitName), nil, nil, TTextLines.LineBreakOf(AWork.Text)), mUsesEdits, mAdded) then
  begin
    Result.Edits := Result.Edits + mUsesEdits;
  end;
end;

/// <summary>Parst die Datei nach den Änderungen nicht mehr fehlerfrei?</summary>
function ParseIssue(AWork: TFileWork; const AEdits: TArray<TTextEdit>): string;
var
  mTree: TSyntaxTree;
begin
  Result := '';
  mTree := TSyntaxTreeCache.Parse(TChangeSignature.ApplyEdits(AWork.Text, AEdits));
  try
    if Length(mTree.Diagnostics) > Length(AWork.Tree.Diagnostics) then
    begin
      Result := cTexts[TEditingMethodWithoutSelfText.AfterTheChangeNoLonger].Fmt([ExtractFileName(AWork.FileName),
        mTree.Diagnostics[0].StartPos.Line + 1, mTree.Diagnostics[0].Message]);
    end;
  finally
    mTree.Free;
  end;
end;

function TMethodBuild.WorkIssue(AWork: TFileWork; out AItem: TMethodFileEdits): string;
begin
  AItem := Default(TMethodFileEdits);
  if Overlapping(AWork.Edits) then
  begin
    Exit(TMethodPlan.Where(AWork.FileName, 0) + cTexts[TEditingMethodWithoutSelfText.NestedCalls].Text);
  end;
  AItem := TextEditsOf(AWork, Plan.UnitName);
  Result := '';
  if AItem.Edits <> nil then
  begin
    Result := ParseIssue(AWork, AItem.Edits);
  end;
end;

/// <summary>Was geschieht, für die Vorschau.</summary>
function ActionText(AConversion: TMethodConversion; const ATarget: TMethodTarget; const AHelperName: string): string;
begin
  case AConversion of
    TMethodConversion.Routine:
      Result := cTexts[TEditingMethodWithoutSelfText.BecomesAFreeRoutine].Fmt([ATarget.ClassName, ATarget.Name]);
    TMethodConversion.Helper:
      Result := cTexts[TEditingMethodWithoutSelfText.MovesToRecordHelperFor].Fmt([ATarget.ClassName, ATarget.Name,
        AHelperName, ATarget.HelperType]);
  else
    Result := cTexts[TEditingMethodWithoutSelfText.BecomesAClassMethod].Fmt([ATarget.ClassName, ATarget.Name]);
  end;
end;

function TMethodBuild.Finish(out AResult: TMethodResult; out AReason: string): Boolean;
var
  mWork: TFileWork;
  mItem: TMethodFileEdits;
begin
  AResult := Default(TMethodResult);
  AReason := '';
  for mWork in Works do
  begin
    AReason := WorkIssue(mWork, mItem);
    if AReason <> '' then
    begin
      Exit(False);
    end;
    if mItem.Edits <> nil then
    begin
      AResult.Files := AResult.Files + [mItem];
    end;
  end;
  AResult.Preview := ActionText(Conversion, Plan.Target, HelperName) +
    cTexts[TEditingMethodWithoutSelfText.ChangedCalls].Fmt([Calls]);
  if PreviewLines <> nil then
  begin
    AResult.Preview := AResult.Preview + sLineBreak + string.Join(sLineBreak, PreviewLines);
  end;
  AResult.Warnings := Warnings;
  AResult.Calls := Calls;
  Result := True;
end;

{ TMethodWithoutSelf }

class function TMethodWithoutSelf.Target(const AText: string; ATree: TSyntaxTree; const APosition: TTextPosition;
  const ALookup: TMethodLookup; out ATarget: TMethodTarget; out AReason: string): Boolean;
var
  mPlan: TMethodPlan;
begin
  ATarget := Default(TMethodTarget);
  AReason := '';
  if (ATree = nil) or (ATree.Root = nil) then
  begin
    Exit(TMethodPlan.Fail(cTexts[TEditingMethodWithoutSelfText.NoTree].Text, AReason));
  end;
  mPlan := TMethodPlan.Create(AText, ATree, ALookup);
  try
    Result := mPlan.Analyze(mPlan.Lines.OffsetAt(APosition), AReason);
    if Result then
    begin
      ATarget := mPlan.Target;
    end;
  finally
    mPlan.Free;
  end;
end;

class function TMethodWithoutSelf.Candidates(const AText: string; ATree: TSyntaxTree;
  const ALookup: TMethodLookup): TArray<TMethodTarget>;
var
  mImplementation_, mRoutine, mHeader: TSyntaxNode;
  mIndex: Integer;
  mFound: TMethodTarget;
  mReason: string;
begin
  Result := nil;
  if (ATree = nil) or (ATree.Root = nil) then
  begin
    Exit;
  end;
  mImplementation_ := ATree.Root.FindChild(TSyntaxKind.ImplementationSection);
  if mImplementation_ = nil then
  begin
    Exit;
  end;
  for mIndex := 0 to mImplementation_.ChildCount - 1 do
  begin
    mRoutine := mImplementation_[mIndex];
    if (mRoutine.Kind <> TSyntaxKind.RoutineDecl) or (TRoutineBody.QualifierOf(mRoutine.Name) = '') then
    begin
      Continue;
    end;
    mHeader := TRoutineParts.HeaderOf(mRoutine);
    if (mHeader <> nil) and Target(AText, ATree, mHeader.EndPos, ALookup, mFound, mReason) then
    begin
      Result := Result + [mFound];
    end;
  end;
end;

class function TMethodWithoutSelf.UseAt(ATree: TSyntaxTree; AOffset: Integer; const AName: string;
  out ACallee, ACall: TSyntaxNode): TMethodUse;
begin
  Result := TMethodPlan.UseAt(ATree, AOffset, AName, ACallee, ACall);
end;

/// <summary>Analyse der Methode und Grund, warum die gewählte Umwandlung nicht geht; '' = geht.</summary>
function ConversionIssue(APlan: TMethodPlan; const ARequest: TMethodRequest): string;
begin
  if not APlan.Analyze(APlan.Lines.OffsetAt(ARequest.Position), Result) then
  begin
    Exit;
  end;
  case ARequest.Conversion of
    TMethodConversion.Routine:
      Result := APlan.Target.RoutineReason;
    TMethodConversion.Helper:
      Result := APlan.Target.HelperReason;
  else
    Result := '';
  end;
end;

procedure AddWorks(ABuild: TMethodBuild; const ADeclaring: TMethodSource; const AOthers: TArray<TMethodSource>);
var
  mSource: TMethodSource;
begin
  ABuild.Works.Add(TFileWork.Create(ADeclaring, True));
  for mSource in AOthers do
  begin
    if (mSource.Tree <> nil) and not SameText(mSource.FileName, ADeclaring.FileName) then
    begin
      ABuild.Works.Add(TFileWork.Create(mSource, False));
    end;
  end;
end;

/// <summary>Deklaration und Kopf der Implementierung zählen nicht als Verwendung.</summary>
function IsOwnHead(APlan: TMethodPlan; AWork: TFileWork; AOffset: Integer): Boolean;
begin
  Result := AWork.Declaring and (TRoutineParts.Encloses(APlan.Declaration, AOffset) or
    TRoutineParts.Encloses(APlan.Header, AOffset));
end;

function SitesIssue(ABuild: TMethodBuild): string;
var
  mWork: TFileWork;
  mOffset: Integer;
begin
  Result := '';
  for mWork in ABuild.Works do
  begin
    for mOffset in mWork.Offsets do
    begin
      if not IsOwnHead(ABuild.Plan, mWork, mOffset) and not ABuild.AddSite(mWork, mOffset, Result) then
      begin
        Exit;
      end;
    end;
  end;
end;

class function TMethodWithoutSelf.Execute(const ADeclaring: TMethodSource; const AOthers: TArray<TMethodSource>;
  const ARequest: TMethodRequest; out AResult: TMethodResult; out AReason: string): Boolean;
var
  mPlan: TMethodPlan;
  mBuild: TMethodBuild;
begin
  AResult := Default(TMethodResult);
  AReason := '';
  if (ADeclaring.Tree = nil) or (ADeclaring.Tree.Root = nil) then
  begin
    AReason := cTexts[TEditingMethodWithoutSelfText.NoTree].Text;
    Exit(False);
  end;
  mPlan := TMethodPlan.Create(ADeclaring.Text, ADeclaring.Tree, ARequest.Lookup);
  mBuild := TMethodBuild.Create(mPlan);
  try
    AReason := ConversionIssue(mPlan, ARequest);
    if AReason = '' then
    begin
      mBuild.Conversion := ARequest.Conversion;
      mBuild.StaticWanted := ARequest.WithStatic;
      mBuild.Style := ARequest.Style;
      AddWorks(mBuild, ADeclaring, AOthers);
      AReason := SitesIssue(mBuild);
    end;
    Result := (AReason = '') and mBuild.DeclaringEdits(AReason) and mBuild.Finish(AResult, AReason);
  finally
    mBuild.Free;
    mPlan.Free;
  end;
end;

class function TMethodWithoutSelf.ConversionName(AConversion: TMethodConversion): string;
begin
  case AConversion of
    TMethodConversion.ClassMethodCalls:
      Result := 'classMethodCalls';
    TMethodConversion.Routine:
      Result := 'routine';
    TMethodConversion.Helper:
      Result := 'helper';
  else
    Result := 'classMethod';
  end;
end;

class function TMethodWithoutSelf.ConversionOf(const AName: string; out AConversion: TMethodConversion): Boolean;
var
  mItem: TMethodConversion;
begin
  for mItem := Low(TMethodConversion) to High(TMethodConversion) do
  begin
    if SameText(ConversionName(mItem), AName) then
    begin
      AConversion := mItem;
      Exit(True);
    end;
  end;
  AConversion := TMethodConversion.ClassMethod;
  Result := False;
end;

class function TMethodWithoutSelf.IsSimpleType(const ATypeName: string): Boolean;
begin
  Result := TMethodPlan.IsSimpleType(ATypeName);
end;

class function TMethodWithoutSelf.HelperNameFor(const ATypeName: string): string;
var
  mName: string;
begin
  mName := Trim(ATypeName);
  if (Length(mName) > 1) and (mName[1] = 'T') and CharInSet(mName[2], ['A'..'Z']) then
  begin
    mName := Copy(mName, 2, MaxInt);
  end;
  if SameText(mName, 'UnicodeString') then
  begin
    mName := 'String';
  end;
  Result := 'T' + Capitalized(mName) + 'Helper';
end;

end.
