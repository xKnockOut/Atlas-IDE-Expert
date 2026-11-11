unit Atlas.Common.Rules.Builtin.FreeFields;

// Felder im Destruktor freigeben (#666):
//   field-not-freed           im Konstruktor erzeugtes Objektfeld, das die
//                             Klasse nirgends freigibt; Korrektur „Im
//                             Destruktor freigeben“. Bis #918 hieß die Regel
//                             owned-field-not-freed (Alias). Komponenten mit
//                             Owner, Interfaces und Klassen aus ignoreTypes
//                             bleiben stumm.
//   owned-field-free-unclear  erzeugtes Feld, das zurückgegeben oder
//                             weitergereicht wird; ob die Klasse es freigeben
//                             muss, entscheidet der Entwickler (ohne Aktion)
//   initialization-not-finalized  (#971) in initialization bzw. class
//                             constructor erzeugtes Objekt einer Unit- bzw.
//                             class-Variablen, das die Unit nirgends freigibt;
//                             Korrektur FreeAndNil in finalization bzw. class
//                             destructor (legt beide bei Bedarf an)
//
// Erkennung und Änderungen liefert TFreeFields (Editing). Mit
// refactoring.freeFields aus schweigen die ersten beiden Regeln.

interface

uses
  System.SysUtils,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry,
  Atlas.Common.Editing.FreeFields;

type
  TOwnedFieldNotFreedRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>True, wenn AField eine Klasse aus AIgnoreTypes erzeugt oder so deklariert ist (#918).</summary>
    class function Ignored(const AField: TOwnedField; const AIgnoreTypes: TArray<string>): Boolean; static;
  end;

  TOwnedFieldFreeUnclearRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TInitializationNotFinalizedRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

procedure RegisterFreeFieldRules(const ARegistry: TRuleRegistry);

implementation

uses
  System.StrUtils,
  System.RegularExpressions,
  System.Generics.Collections,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Editing.UsesClause,
  Atlas.Common.Rules.Options,
  Atlas.Text.Lines,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Befundmeldungen in beiden Sprachen (#1458).</summary>
  TFreeFieldsText = (LeakTitle, Leak, UnclearTitle, Unclear, InitNotFinal, FreeInFinalization, ClassCtorNotFreed,
    FreeInClassDestructor, StartTitle);

const
  cTexts: array[TFreeFieldsText] of TAtlasText = (
    (De: 'Im Konstruktor erzeugtes Feld wird nicht freigegeben'; En: 'Field created in the constructor is not freed'),
    (De: '%s wird im Konstruktor erzeugt, aber im Destruktor nicht freigegeben (Speicherleck).';
     En: '%s is created in the constructor but not freed in the destructor (memory leak).'),
    (De: 'Unklar, ob ein erzeugtes Feld freigegeben werden muss'; En: 'Unclear whether a created field must be freed'),
    (De: '"%s" wird in %s erzeugt und nicht freigegeben; ob %s es freigeben muss, ist unklar: Es %s';
     En: '"%s" is created in %s and not freed; whether %s must free it is unclear: it %s'),
    (De: '%s wird in initialization erzeugt, aber in finalization nicht freigegeben.';
     En: '%s is created in initialization but not freed in finalization.'),
    (De: 'In finalization freigeben'; En: 'Free in finalization'),
    (De: '%s wird im class constructor erzeugt, aber im class destructor nicht freigegeben.';
     En: '%s is created in the class constructor but not freed in the class destructor.'),
    (De: 'Im class destructor freigeben'; En: 'Free in the class destructor'),
    (De: 'Beim Start erzeugtes Objekt wird nicht freigegeben'; En: 'Object created at startup is not freed'));

{$SCOPEDENUMS OFF}

{ TOwnedFieldNotFreedRule }

function TOwnedFieldNotFreedRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('field-not-freed', TRuleSeverity.Warning,
    cTexts[TFreeFieldsText.LeakTitle].Text);
end;

class function TOwnedFieldNotFreedRule.Ignored(const AField: TOwnedField; const AIgnoreTypes: TArray<string>): Boolean;
var
  mDeclared: string;
begin
  // Generische Typen vergleichen ohne Typparameter: TObjectList<TFoo> -> TObjectList.
  mDeclared := AField.TypeName;
  if Pos('<', mDeclared) > 0 then
  begin
    mDeclared := Copy(mDeclared, 1, Pos('<', mDeclared) - 1);
  end;
  Result := MatchText(Trim(AField.CreatedType), AIgnoreTypes) or MatchText(Trim(mDeclared), AIgnoreTypes) or
    MatchText(Trim(AField.TypeName), AIgnoreTypes);
end;

procedure TOwnedFieldNotFreedRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mField: TOwnedField;
  mStyle: TFreeFieldsStyle;
  mEdits: TArray<TTextEdit>;
  mFixes: TArray<TRuleFix>;
  mIgnoreTypes: TArray<string>;
begin
  if (AContext.Tree = nil) or AContext.NoFreeFields then
  begin
    Exit;
  end;
  mIgnoreTypes := TRuleOptions.Strings(AContext.Options, 'ignoreTypes', nil);
  mStyle := TFreeFieldsStyle.Free;
  if AContext.FreeFieldsFreeAndNil then
  begin
    mStyle := TFreeFieldsStyle.FreeAndNil;
  end;
  for mField in TFreeFields.Analyze(AContext.Tree, AContext.Text, AContext.Index) do
  begin
    if (mField.State <> TOwnedFieldState.NotFreed) or Ignored(mField, mIgnoreTypes) then
    begin
      Continue;
    end;
    mFixes := nil;
    // Nicht sicher: Ob die Klasse das Objekt besitzt, weiß nur der Entwickler.
    if TFreeFields.Edits(AContext.Tree, AContext.Text, [mField], mStyle, mEdits) then
    begin
      mFixes := [TRuleFix.Create(TFreeFields.FieldTitle, mEdits, False)];
    end;
    // Mittel: Ob das Objekt anderswo freigegeben wird, sieht die Regel nicht immer.
    AReport.Add(mField.Range, cTexts[TFreeFieldsText.Leak].Fmt([mField.Name]), TRuleConfidence.Medium, mFixes);
  end;
end;

{ TOwnedFieldFreeUnclearRule }

function TOwnedFieldFreeUnclearRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('owned-field-free-unclear', TRuleSeverity.Hint,
    cTexts[TFreeFieldsText.UnclearTitle].Text);
end;

procedure TOwnedFieldFreeUnclearRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mField: TOwnedField;
begin
  if (AContext.Tree = nil) or AContext.NoFreeFields then
  begin
    Exit;
  end;
  for mField in TFreeFields.Analyze(AContext.Tree, AContext.Text, AContext.Index) do
  begin
    if mField.State = TOwnedFieldState.Unclear then
    begin
      AReport.Add(mField.Range, cTexts[TFreeFieldsText.Unclear].Fmt([mField.Name, mField.CreatedIn, mField.ClassName,
        mField.Reason]));
    end;
  end;
end;

{ TInitializationNotFinalizedRule }

const
  cInitializationNotFinalizedRuleId = 'initialization-not-finalized';
  /// <summary>Aufrufe am Objekt, die es freigeben.</summary>
  cReleasingMethods: array[0..3] of string = ('Free', 'Destroy', 'DisposeOf', 'Release');

type
  /// <summary>Ein in initialization bzw. class constructor erzeugtes Objekt (#971).</summary>
  TInitCreation = record
    Name: string;
    /// <summary>Die Zuweisung mit Create; dort steht die Meldung.</summary>
    Assignment: TSyntaxNode;
    /// <summary>Klasse der class var; nil bei einer Unit-Variablen.</summary>
    ClassDecl: TSyntaxNode;
    /// <summary>Andere Units erreichen die Variable (interface-Abschnitt, nicht private).</summary>
    Visible: Boolean;
    /// <summary>Offsets der Deklaration: Name und Typ.</summary>
    DeclStart, DeclEnd: Integer;
  end;

  /// <summary>Unit- bzw. class-Variable mit Objekttyp.</summary>
  TInitVariable = record
    Name: string;
    ClassDecl: TSyntaxNode;
    Visible: Boolean;
    DeclStart, DeclEnd: Integer;
  end;

  /// <summary>Sucht alle Erwähnungen einer Variablen in der Unit: gibt die Unit sie frei, oder gibt sie sie
  /// weiter? Nur harmlose Erwähnungen (Mitglied lesen oder aufrufen, mit nil vergleichen, Assigned, neu
  /// erzeugen oder nil zuweisen) lassen die Meldung zu; jede andere könnte das Objekt übergeben.</summary>
  TInitUses = class
  private
    FContext: TRuleContext;
    FName: string;
    FClassName: string;
    FFreed: Boolean;
    FEscaped: Boolean;
    FHarmless: TArray<TSyntaxNode>;
    function IsRef(ANode: TSyntaxNode): Boolean;
    procedure Harmless(ANode: TSyntaxNode);
    procedure VisitMember(ANode: TSyntaxNode);
    procedure VisitCall(ANode: TSyntaxNode);
    procedure VisitCompare(ANode: TSyntaxNode);
    procedure VisitAssign(ANode: TSyntaxNode);
    procedure Visit(ARoot: TSyntaxNode);
  public
    constructor Create(const AContext: TRuleContext; const ACreation: TInitCreation);
    /// <summary>True, wenn die Unit das Objekt nirgends freigibt und nirgends weitergibt.</summary>
    function Leaks(const ACreation: TInitCreation): Boolean;
  end;

constructor TInitUses.Create(const AContext: TRuleContext; const ACreation: TInitCreation);
begin
  inherited Create;
  FContext := AContext;
  FName := ACreation.Name;
  if ACreation.ClassDecl <> nil then
  begin
    FClassName := ACreation.ClassDecl.Name;
  end;
end;

function TInitUses.IsRef(ANode: TSyntaxNode): Boolean;
begin
  Result := False;
  if ANode = nil then
  begin
    Exit;
  end;
  if ANode.Kind = TSyntaxKind.Identifier then
  begin
    Exit(SameText(ANode.Name, FName));
  end;
  // Self.FInstanz bzw. TKlasse.FInstanz
  Result := (FClassName <> '') and (ANode.Kind = TSyntaxKind.MemberAccess) and SameText(ANode.Name, FName) and
    (ANode.ChildCount = 1) and (ANode[0].Kind = TSyntaxKind.Identifier) and
    (SameText(ANode[0].Name, 'Self') or SameText(ANode[0].Name, FClassName));
end;

procedure TInitUses.Harmless(ANode: TSyntaxNode);
begin
  FHarmless := FHarmless + [ANode];
end;

/// <summary>X.Free u. a. gibt frei, X.FreeOnTerminate gibt weiter (ein Thread, der sich selbst freigibt);
/// jedes andere Mitglied ist harmlos.</summary>
procedure TInitUses.VisitMember(ANode: TSyntaxNode);
begin
  if (ANode.ChildCount < 1) or not IsRef(ANode[0]) then
  begin
    Exit;
  end;
  if MatchText(ANode.Name, cReleasingMethods) then
  begin
    FFreed := True;
  end
  else if SameText(ANode.Name, 'FreeOnTerminate') then
  begin
    FEscaped := True;
  end
  else
  begin
    Harmless(ANode[0]);
  end;
end;

/// <summary>FreeAndNil(X) gibt frei, Assigned(X) ist harmlos.</summary>
procedure TInitUses.VisitCall(ANode: TSyntaxNode);
begin
  if (ANode.ChildCount <> 2) or (ANode[0].Kind <> TSyntaxKind.Identifier) or not IsRef(ANode[1]) then
  begin
    Exit;
  end;
  if SameText(ANode[0].Name, 'FreeAndNil') then
  begin
    FFreed := True;
  end
  else if SameText(ANode[0].Name, 'Assigned') then
  begin
    Harmless(ANode[1]);
  end;
end;

/// <summary>Vergleiche mit X (gleich, ungleich) sind harmlos.</summary>
procedure TInitUses.VisitCompare(ANode: TSyntaxNode);
var
  mIndex: Integer;
begin
  if (ANode.Name <> '=') and (ANode.Name <> '<>') then
  begin
    Exit;
  end;
  for mIndex := 0 to ANode.ChildCount - 1 do
  begin
    if IsRef(ANode[mIndex]) then
    begin
      Harmless(ANode[mIndex]);
    end;
  end;
end;

/// <summary>X := nil und X := TKlasse.Create (ohne Besitzer) sind harmlos.</summary>
procedure TInitUses.VisitAssign(ANode: TSyntaxNode);
var
  mTypeName: string;
  mOwned, mReset: Boolean;
begin
  if (ANode.ChildCount < 2) or not IsRef(ANode[0]) then
  begin
    Exit;
  end;
  mReset := (ANode[1].Kind = TSyntaxKind.Literal) and SameText(ANode[1].Name, 'nil');
  if mReset or (TFreeFields.ObjectCreation(FContext.Tree, FContext.Text, FContext.Index, ANode[1], mTypeName,
    mOwned) and not mOwned) then
  begin
    Harmless(ANode[0]);
  end;
end;

// Iterativ (tiefe Bäume sprengen den Stapel nicht).
procedure TInitUses.Visit(ARoot: TSyntaxNode);
var
  mPending: TStack<TSyntaxNode>;
  mNode: TSyntaxNode;
  mIndex: Integer;
begin
  mPending := TStack<TSyntaxNode>.Create;
  try
    mPending.Push(ARoot);
    while mPending.Count > 0 do
    begin
      mNode := mPending.Pop;
      case mNode.Kind of
        TSyntaxKind.MemberAccess:
          VisitMember(mNode);
        TSyntaxKind.Call:
          VisitCall(mNode);
        TSyntaxKind.BinaryExpr:
          VisitCompare(mNode);
        TSyntaxKind.AssignStatement:
          VisitAssign(mNode);
      else
        // Übrige Werte bewusst ohne Wirkung.
      end;
      for mIndex := mNode.ChildCount - 1 downto 0 do
      begin
        mPending.Push(mNode[mIndex]);
      end;
    end;
  finally
    mPending.Free;
  end;
end;

function TInitUses.Leaks(const ACreation: TInitCreation): Boolean;
var
  mToken: TPascalToken;
  mNode: TSyntaxNode;
  mKnown: Boolean;
begin
  Visit(FContext.Tree.Root);
  if FFreed or FEscaped then
  begin
    Exit(False);
  end;
  // Jede Erwähnung im Text muss eine der harmlosen sein (auch in Properties, with und asm).
  for mToken in FContext.Tree.Tokens do
  begin
    if (mToken.Kind <> TPascalTokenKind.Identifier) or not SameText(mToken.Text, FName) or
      ((mToken.Offset >= ACreation.DeclStart) and (mToken.Offset < ACreation.DeclEnd)) then
    begin
      Continue;
    end;
    mKnown := False;
    for mNode in FHarmless do
    begin
      if (mToken.Offset >= mNode.StartOffset) and (mToken.Offset < mNode.EndOffset) then
      begin
        mKnown := True;
      end;
    end;
    if not mKnown then
    begin
      Exit(False);
    end;
  end;
  Result := True;
end;

/// <summary>Verwendet eine andere Unit des Index den Namen? Dann könnte sie das Objekt freigeben.</summary>
function UsedElsewhere(const AContext: TRuleContext; const AName: string): Boolean;
var
  mUnitIndex: TUnitIndex;
  mUsage: TIndexUsage;
begin
  Result := False;
  if AContext.Index = nil then
  begin
    Exit;
  end;
  for mUnitIndex in AContext.Index.Units do
  begin
    if not SameText(mUnitIndex.UnitName, AContext.UnitName) then
    begin
      for mUsage in mUnitIndex.Usages do
      begin
        if SameText(mUsage.Name, AName) then
        begin
          Exit(True);
        end;
      end;
    end;
  end;
end;

/// <summary>Typname der Deklaration, '' ohne einfachen Typverweis.</summary>
function DeclaredType(const AText: string; ADecl: TSyntaxNode): string;
var
  mTypeRef: TSyntaxNode;
begin
  Result := '';
  mTypeRef := ADecl.FindChild(TSyntaxKind.TypeReference);
  if mTypeRef <> nil then
  begin
    Result := Trim(Copy(AText, mTypeRef.StartOffset + 1, mTypeRef.EndOffset - mTypeRef.StartOffset));
  end;
end;

/// <summary>Steht vor ANode das Schlüsselwort class (class var)?</summary>
function AfterClassKeyword(const ATokens: TArray<TPascalToken>; ANode: TSyntaxNode): Boolean;
var
  mIndex: Integer;
begin
  Result := False;
  for mIndex := High(ATokens) downto 0 do
  begin
    if ATokens[mIndex].Offset < ANode.StartOffset then
    begin
      if ATokens[mIndex].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive] then
      begin
        Continue;
      end;
      Exit(ATokens[mIndex].IsKeyword('class'));
    end;
  end;
end;

/// <summary>Variablen mit Objekttyp aus dem var-Abschnitt AVars; AClassDecl: Klasse der class var, nil bei
/// Unit-Variablen; AVisible: für andere Units erreichbar.</summary>
procedure AddObjectVariables(const AContext: TRuleContext; AVars, AClassDecl: TSyntaxNode; AVisible: Boolean;
  var AVariables: TArray<TInitVariable>);
var
  mDecl: TSyntaxNode;
  mIndex: Integer;
  mVariable: TInitVariable;
  mName: string;
begin
  for mIndex := 0 to AVars.ChildCount - 1 do
  begin
    mDecl := AVars[mIndex];
    if (mDecl.Kind <> TSyntaxKind.VarDecl) or (DeclaredType(AContext.Text, mDecl) = '') or
      not TFreeFields.IsObjectType(AContext.Tree, AContext.Text, AContext.Index,
        DeclaredType(AContext.Text, mDecl)) then
    begin
      Continue;
    end;
    for mName in mDecl.Name.Split([',']) do
    begin
      mVariable := Default(TInitVariable);
      mVariable.Name := Trim(mName);
      mVariable.ClassDecl := AClassDecl;
      mVariable.Visible := AVisible;
      mVariable.DeclStart := mDecl.StartOffset;
      mVariable.DeclEnd := mDecl.EndOffset;
      AVariables := AVariables + [mVariable];
    end;
  end;
end;

/// <summary>class vars mit Objekttyp der Klasse ATypeDecl; private sind für andere Units nicht sichtbar.</summary>
procedure AddClassVariables(const AContext: TRuleContext; ATypeDecl: TSyntaxNode; AVisible: Boolean;
  var AVariables: TArray<TInitVariable>);
var
  mClassNode, mMember: TSyntaxNode;
  mIndex: Integer;
  mVisibility: string;
begin
  mClassNode := ATypeDecl.FindChild(TSyntaxKind.ClassType);
  if (ATypeDecl.Kind <> TSyntaxKind.TypeDecl) or (mClassNode = nil) then
  begin
    Exit;
  end;
  mVisibility := 'public';
  for mIndex := 0 to mClassNode.ChildCount - 1 do
  begin
    mMember := mClassNode[mIndex];
    if mMember.Kind = TSyntaxKind.Visibility then
    begin
      mVisibility := mMember.Name;
    end;
    if (mMember.Kind = TSyntaxKind.VarSection) and AfterClassKeyword(AContext.Tree.Tokens, mMember) then
    begin
      AddObjectVariables(AContext, mMember, ATypeDecl, AVisible and not ContainsText(mVisibility, 'private'),
        AVariables);
    end;
  end;
end;

/// <summary>Variablen mit Objekttyp aus dem Abschnitt ASection: Unit-Variablen (var) und class vars der
/// Klassen darin.</summary>
procedure ReadVariables(const AContext: TRuleContext; ASection: TSyntaxNode; AVisible: Boolean;
  var AVariables: TArray<TInitVariable>);
var
  mChild: TSyntaxNode;
  mIndex, mTypeIndex: Integer;
begin
  for mIndex := 0 to ASection.ChildCount - 1 do
  begin
    mChild := ASection[mIndex];
    if (mChild.Kind = TSyntaxKind.VarSection) and SameText(mChild.Name, 'var') then
    begin
      AddObjectVariables(AContext, mChild, nil, AVisible, AVariables);
    end
    else if mChild.Kind = TSyntaxKind.TypeSection then
    begin
      for mTypeIndex := 0 to mChild.ChildCount - 1 do
      begin
        AddClassVariables(AContext, mChild[mTypeIndex], AVisible, AVariables);
      end;
    end;
  end;
end;

/// <summary>Name der Variablen, der ATarget zuweist: X, im class constructor auch Self.X oder TKlasse.X;
/// '' sonst.</summary>
function AssignedName(ATarget, AClassDecl: TSyntaxNode): string;
begin
  Result := '';
  if ATarget.Kind = TSyntaxKind.Identifier then
  begin
    Result := ATarget.Name;
  end
  else if (AClassDecl <> nil) and (ATarget.Kind = TSyntaxKind.MemberAccess) and (ATarget.ChildCount = 1) and
    (ATarget[0].Kind = TSyntaxKind.Identifier) then
  begin
    if SameText(ATarget[0].Name, 'Self') or SameText(ATarget[0].Name, AClassDecl.Name) then
    begin
      Result := ATarget.Name;
    end;
  end;
end;

/// <summary>Steht die Erzeugung von AName in AClassDecl schon in ACreations?</summary>
function KnownCreation(const ACreations: TArray<TInitCreation>; const AName: string; AClassDecl: TSyntaxNode):
  Boolean;
var
  mCreation: TInitCreation;
begin
  Result := False;
  for mCreation in ACreations do
  begin
    Result := Result or (SameText(mCreation.Name, AName) and (mCreation.ClassDecl = AClassDecl));
  end;
end;

/// <summary>Nimmt die Zuweisung AAssign auf, wenn sie einer Variablen aus AVariables ein neues Objekt ohne
/// Besitzer zuweist.</summary>
procedure AddCreation(const AContext: TRuleContext; AAssign, AClassDecl: TSyntaxNode;
  const AVariables: TArray<TInitVariable>; var ACreations: TArray<TInitCreation>);
var
  mVariable: TInitVariable;
  mCreation: TInitCreation;
  mTypeName, mName: string;
  mOwned: Boolean;
begin
  mName := AssignedName(AAssign[0], AClassDecl);
  if (mName = '') or KnownCreation(ACreations, mName, AClassDecl) or not TFreeFields.ObjectCreation(AContext.Tree,
    AContext.Text, AContext.Index, AAssign[1], mTypeName, mOwned) or mOwned then
  begin
    Exit;
  end;
  for mVariable in AVariables do
  begin
    if SameText(mVariable.Name, mName) and (mVariable.ClassDecl = AClassDecl) then
    begin
      mCreation := Default(TInitCreation);
      mCreation.Name := mVariable.Name;
      mCreation.Assignment := AAssign;
      mCreation.ClassDecl := AClassDecl;
      mCreation.Visible := mVariable.Visible;
      mCreation.DeclStart := mVariable.DeclStart;
      mCreation.DeclEnd := mVariable.DeclEnd;
      ACreations := ACreations + [mCreation];
      Exit;
    end;
  end;
end;

/// <summary>Zuweisungen Variable := TKlasse.Create… in ANode (ohne anonyme Methoden); AClassDecl nil für
/// initialization, sonst die Klasse des class constructor. Iterativ (tiefe Bäume sprengen den Stapel nicht).</summary>
procedure FindCreations(const AContext: TRuleContext; ANode, AClassDecl: TSyntaxNode;
  const AVariables: TArray<TInitVariable>; var ACreations: TArray<TInitCreation>);
var
  mPending: TStack<TSyntaxNode>;
  mNode: TSyntaxNode;
  mIndex: Integer;
begin
  mPending := TStack<TSyntaxNode>.Create;
  try
    mPending.Push(ANode);
    while mPending.Count > 0 do
    begin
      mNode := mPending.Pop;
      if mNode.Kind = TSyntaxKind.AnonymousMethod then
      begin
        Continue;
      end;
      if (mNode.Kind = TSyntaxKind.AssignStatement) and (mNode.ChildCount >= 2) then
      begin
        AddCreation(AContext, mNode, AClassDecl, AVariables, ACreations);
      end;
      for mIndex := mNode.ChildCount - 1 downto 0 do
      begin
        mPending.Push(mNode[mIndex]);
      end;
    end;
  finally
    mPending.Free;
  end;
end;

/// <summary>Letztes Token bei oder vor AIndex, das kein Kommentar und keine Direktive ist; -1 ohne.</summary>
function CodeBefore(const ATokens: TArray<TPascalToken>; AIndex: Integer): Integer;
begin
  Result := AIndex;
  while (Result >= 0) and (ATokens[Result].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]) do
  begin
    Dec(Result);
  end;
end;

/// <summary>Das "end" vor dem letzten Punkt der Unit; -1 ohne.</summary>
function UnitEndIndex(const ATokens: TArray<TPascalToken>): Integer;
var
  mIndex, mPrevious: Integer;
begin
  Result := -1;
  for mIndex := High(ATokens) downto 1 do
  begin
    if ATokens[mIndex].IsSymbol('.') then
    begin
      mPrevious := CodeBefore(ATokens, mIndex - 1);
      if (mPrevious >= 0) and ATokens[mPrevious].IsKeyword('end') then
      begin
        Result := mPrevious;
      end;
      Exit;
    end;
  end;
end;

/// <summary>Neuer finalization-Abschnitt mit AStatement vor der Zeile ALine; mit Leerzeile davor, wenn die
/// Zeile darüber nicht leer ist.</summary>
function NewFinalization(const ALines: TArray<string>; ALine: Integer; const AStatement, ALineBreak: string): string;
begin
  Result := 'finalization' + ALineBreak + '  ' + AStatement + ALineBreak;
  if (ALine = 0) or (Trim(ALines[ALine - 1]) <> '') then
  begin
    Result := ALineBreak + Result;
  end;
end;

/// <summary>"FreeAndNil(X);" vor das "end." der Unit, in finalization; fehlt sie, wird sie angelegt.
/// ACreated: finalization wurde angelegt.</summary>
function FinalizationEdits(const AContext: TRuleContext; const AStatement: string; out AEdits: TArray<TTextEdit>;
  out ACreated: Boolean): Boolean;
var
  mTokens: TArray<TPascalToken>;
  mLines: TArray<string>;
  mLineBreak, mText: string;
  mEnd, mPrevious, mLine: Integer;
begin
  AEdits := nil;
  ACreated := False;
  mTokens := AContext.Tree.Tokens;
  mEnd := UnitEndIndex(mTokens);
  Result := mEnd >= 1;
  if not Result then
  begin
    Exit;
  end;
  mLines := TTextLines.SplitLines(AContext.Text, mLineBreak);
  mLine := mTokens[mEnd].StartPos.Line;
  // Nur wenn "end." am Zeilenanfang steht; sonst gäbe es keine saubere Stelle.
  Result := (mLine <= High(mLines)) and (Trim(Copy(mLines[mLine], 1, mTokens[mEnd].StartPos.Character)) = '');
  if not Result then
  begin
    Exit;
  end;
  mPrevious := CodeBefore(mTokens, mEnd - 1);
  if AContext.Tree.Root.FindChild(TSyntaxKind.FinalizationSection) <> nil then
  begin
    // Letzte Anweisung ohne Semikolon: erst eins ergänzen.
    if (mPrevious >= 0) and not mTokens[mPrevious].IsSymbol(';') and
      not mTokens[mPrevious].IsKeyword('finalization') then
    begin
      AEdits := [TTextEdit.Create(TTextRange.Create(mTokens[mPrevious].EndPos, mTokens[mPrevious].EndPos), ';')];
    end;
    mText := '  ' + AStatement + mLineBreak;
  end
  else
  begin
    ACreated := True;
    mText := NewFinalization(mLines, mLine, AStatement, mLineBreak);
  end;
  AEdits := AEdits + [TTextEdit.Create(TTextRange.Create(TTextPosition.Create(mLine, 0),
    TTextPosition.Create(mLine, 0)), mText)];
end;

/// <summary>Variablen mit Objekttyp aus interface und implementation.</summary>
function UnitVariables(const AContext: TRuleContext): TArray<TInitVariable>;
var
  mSection: TSyntaxNode;
begin
  Result := nil;
  mSection := AContext.Tree.Root.FindChild(TSyntaxKind.InterfaceSection);
  if mSection <> nil then
  begin
    ReadVariables(AContext, mSection, True, Result);
  end;
  mSection := AContext.Tree.Root.FindChild(TSyntaxKind.ImplementationSection);
  if mSection <> nil then
  begin
    ReadVariables(AContext, mSection, False, Result);
  end;
end;

/// <summary>Ist ADecl ein class constructor mit Rumpf?</summary>
function IsClassConstructor(const AContext: TRuleContext; ADecl: TSyntaxNode): Boolean;
var
  mHeader: TSyntaxNode;
begin
  mHeader := ADecl.FindChild(TSyntaxKind.RoutineHeader);
  Result := (ADecl.Kind = TSyntaxKind.RoutineDecl) and (mHeader <> nil) and
    (ADecl.FindChild(TSyntaxKind.Block) <> nil);
  Result := Result and TRegEx.IsMatch(Copy(AContext.Text, mHeader.StartOffset + 1, mHeader.EndOffset -
    mHeader.StartOffset), '^class\s+constructor\b', [roIgnoreCase]);
end;

/// <summary>Erzeugungen in den class constructors der Klassen mit class vars.</summary>
procedure AddClassConstructorCreations(const AContext: TRuleContext; const AVariables: TArray<TInitVariable>;
  var ACreations: TArray<TInitCreation>);
var
  mSection, mDecl: TSyntaxNode;
  mIndex: Integer;
  mVariable: TInitVariable;
begin
  mSection := AContext.Tree.Root.FindChild(TSyntaxKind.ImplementationSection);
  if mSection = nil then
  begin
    Exit;
  end;
  for mIndex := 0 to mSection.ChildCount - 1 do
  begin
    mDecl := mSection[mIndex];
    if not IsClassConstructor(AContext, mDecl) then
    begin
      Continue;
    end;
    for mVariable in AVariables do
    begin
      if (mVariable.ClassDecl <> nil) and StartsText(mVariable.ClassDecl.Name + '.', mDecl.Name) then
      begin
        FindCreations(AContext, mDecl.FindChild(TSyntaxKind.Block), mVariable.ClassDecl, AVariables, ACreations);
        Break;
      end;
    end;
  end;
end;

/// <summary>Erzeugungen der Variablen AVariables in initialization und in class constructors.</summary>
function CollectCreations(const AContext: TRuleContext; const AVariables: TArray<TInitVariable>):
  TArray<TInitCreation>;
var
  mSection: TSyntaxNode;
  mVariable: TInitVariable;
  mHasClassVars: Boolean;
begin
  Result := nil;
  mSection := AContext.Tree.Root.FindChild(TSyntaxKind.InitializationSection);
  if mSection <> nil then
  begin
    FindCreations(AContext, mSection, nil, AVariables, Result);
  end;
  mHasClassVars := False;
  for mVariable in AVariables do
  begin
    mHasClassVars := mHasClassVars or (mVariable.ClassDecl <> nil);
  end;
  if mHasClassVars then
  begin
    AddClassConstructorCreations(AContext, AVariables, Result);
  end;
end;

/// <summary>Gibt die Unit ACreation nirgends frei und nirgends weiter, und keine andere Unit sieht sie?</summary>
function IsLeak(const AContext: TRuleContext; const ACreation: TInitCreation): Boolean;
var
  mScan: TInitUses;
begin
  mScan := TInitUses.Create(AContext, ACreation);
  try
    Result := mScan.Leaks(ACreation);
  finally
    mScan.Free;
  end;
  Result := Result and not (ACreation.Visible and UsedElsewhere(AContext, ACreation.Name));
end;

/// <summary>Änderungen zum Freigeben von ACreation in finalization bzw. im class destructor; ASafe: als
/// sichere Korrektur anwendbar (kein neu angelegter Abschnitt).</summary>
function ReleaseEdits(const AContext: TRuleContext; const ACreation: TInitCreation; out ASafe: Boolean):
  TArray<TTextEdit>;
var
  mStatement: string;
  mCreated: Boolean;
begin
  mStatement := Format('FreeAndNil(%s);', [ACreation.Name]);
  if ACreation.ClassDecl = nil then
  begin
    ASafe := FinalizationEdits(AContext, mStatement, Result, mCreated) and not mCreated;
  end
  else
  begin
    if not TFreeFields.ClassDestructorEdits(AContext.Tree, AContext.Text, ACreation.ClassDecl, [mStatement],
      Result) then
    begin
      Result := nil;
    end;
    ASafe := Length(Result) = 1;
  end;
end;

/// <summary>Ergänzt AEdits um System.SysUtils in uses, wenn es fehlt; nil, wenn das nicht geht. Mehrere neu
/// angelegte Abschnitte oder uses-Einträge an derselben Stelle vertragen sich nicht: solche Korrekturen nur
/// einzeln (nicht sicher).</summary>
procedure AddSysUtils(const AContext: TRuleContext; const ACreation: TInitCreation; var AEdits: TArray<TTextEdit>;
  var ASafe: Boolean);
var
  mUsesEdit: TTextEdit;
begin
  if (AEdits = nil) or TUsesClauses.IsUsed(TUsesClauses.UsedUnits(AContext.Tree.Tokens), 'System.SysUtils',
    AContext.Namespaces) then
  begin
    Exit;
  end;
  if TUsesClauses.AddUnit(AContext.Tree.Tokens, ACreation.Assignment.StartOffset, 'System.SysUtils',
    TTextLines.LineBreakOf(AContext.Text), mUsesEdit) then
  begin
    AEdits := AEdits + [mUsesEdit];
    ASafe := False;
  end
  else
  begin
    AEdits := nil;
  end;
end;

/// <summary>Meldung und Titel der Korrektur für ACreation.</summary>
function LeakMessage(const ACreation: TInitCreation; out ATitle: string): string;
begin
  if ACreation.ClassDecl = nil then
  begin
    Result := cTexts[TFreeFieldsText.InitNotFinal].Fmt([ACreation.Name]);
    ATitle := cTexts[TFreeFieldsText.FreeInFinalization].Text;
  end
  else
  begin
    Result := cTexts[TFreeFieldsText.ClassCtorNotFreed].Fmt([ACreation.Name]);
    ATitle := cTexts[TFreeFieldsText.FreeInClassDestructor].Text;
  end;
end;

function TInitializationNotFinalizedRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(cInitializationNotFinalizedRuleId, TRuleSeverity.Warning,
    cTexts[TFreeFieldsText.StartTitle].Text);
end;

procedure TInitializationNotFinalizedRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mVariables: TArray<TInitVariable>;
  mCreation: TInitCreation;
  mEdits: TArray<TTextEdit>;
  mSafe: Boolean;
  mFixes: TArray<TRuleFix>;
  mMessage, mTitle: string;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
  begin
    Exit;
  end;
  mVariables := UnitVariables(AContext);
  if mVariables = nil then
  begin
    Exit;
  end;
  for mCreation in CollectCreations(AContext, mVariables) do
  begin
    if not IsLeak(AContext, mCreation) then
    begin
      Continue;
    end;
    mMessage := LeakMessage(mCreation, mTitle);
    mEdits := ReleaseEdits(AContext, mCreation, mSafe);
    AddSysUtils(AContext, mCreation, mEdits, mSafe);
    mFixes := nil;
    if mEdits <> nil then
    begin
      mFixes := [TRuleFix.Create(mTitle, mEdits, mSafe)];
    end;
    AReport.Add(TTextRange.Create(mCreation.Assignment[0].StartPos, mCreation.Assignment[0].EndPos), mMessage,
      TRuleConfidence.High, mFixes);
  end;
end;

procedure RegisterFreeFieldRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TOwnedFieldNotFreedRule.Create);
  ARegistry.Register(TOwnedFieldFreeUnclearRule.Create);
  ARegistry.Register(TInitializationNotFinalizedRule.Create);
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.FreeFields', cTexts);

end.
