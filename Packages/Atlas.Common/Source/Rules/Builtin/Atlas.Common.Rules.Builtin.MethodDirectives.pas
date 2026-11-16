unit Atlas.Common.Rules.Builtin.MethodDirectives;

// Direktiven an Methoden und Klassen (#909, Gruppe Compiler vorab):
//   abstract-declaration-invalid  abstract, final oder static falsch kombiniert
//                                 (#998): abstract ohne virtual oder dynamic
//                                 (E2167), Rumpf zu einer abstrakten Methode
//                                 (E2136), final ohne virtual (E2351), abstract
//                                 zusammen mit final (E2371), eine Klasse
//                                 abstract sealed (E2383) und static an einer
//                                 Instanzmethode oder virtuellen Klassenmethode
//                                 (E2376). Eine Klasse sealed mit offenen
//                                 abstrakten Methoden (#1380): an der Klasse
//                                 E2540 und je Methode E2539, an einer eigenen
//                                 abstrakten Methode zusätzlich E2383;
//                                 abstract sealed meldet auch E2540 (wie dcc in
//                                 Cm.E2383, Cm.E2539, Cm.E2540).
//
// Die Regel liest die Direktiven aus dem Syntaxbaum. Nur für geerbte abstrakte
// Methoden fragt sie Datei und Index über TAncestry (wie
// abstract-class-instantiated); bricht die Kette der Vorfahren ab, fehlen nur
// die Methoden jenseits der Lücke.
// override und message zählen wie virtual (override; abstract; deklariert eine
// geerbte Methode neu als abstrakt). Ein Rumpf gilt nur dann als Rumpf einer
// abstrakten Methode, wenn keine gleichnamige nicht abstrakte Methode derselben
// Klasse mit ihm übersetzt wird (Überladungen, Zweige von {$IFDEF} über
// TConditionalBranches).
//
// Korrekturen: "virtual;" vor abstract einfügen (E2167) bzw. den Rumpf
// entfernen (E2136).

interface

uses
  System.SysUtils,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry;

const
  cAbstractDeclarationInvalidRuleId = 'abstract-declaration-invalid';

type
  TAbstractDeclarationInvalidRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

procedure RegisterMethodDirectiveRules(const ARegistry: TRuleRegistry);

implementation

uses
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.ConditionalBranches,
  Atlas.Common.Pascal.TokenCursor,
  Atlas.Common.Rules.Derived,
  Atlas.Common.Rules.Builtin.Inheritance,
  Atlas.Text.Lines,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Befundmeldungen in beiden Sprachen (#1458).</summary>
  TMethodDirectivesText = (Title, AbstractVirtual, InsertVirtual, AbstractFinal, FinalVirtual, StaticInstance,
    StaticVirtual, AbstractSealedTitle, AbstractInSealed, SealedNotImplemented, SealedWithAbstract, SealedAbstract,
    RemoveBody, AbstractBody);

const
  cTexts: array[TMethodDirectivesText] of TAtlasText = (
    (De: 'abstract, final oder static falsch kombiniert'; En: 'abstract, final or static combined incorrectly'),
    (De: 'abstract nur zusammen mit virtual oder dynamic (wie E2167).';
     En: 'abstract only together with virtual or dynamic (like E2167).'),
    (De: '"virtual;" vor abstract einfügen'; En: 'Insert "virtual;" before abstract'),
    (De: '%s ist abstract und final zugleich; eine abstrakte Methode muss sich überschreiben lassen (wie E2371).';
     En: '%s is abstract and final at the same time; an abstract method must be overridable (like E2371).'),
    (De: 'final nur an virtuellen Methoden; %s ist nicht virtual, dynamic oder override (wie E2351).';
     En: 'final only on virtual methods; %s is not virtual, dynamic or override (like E2351).'),
    (De: 'static nur an Klassenmethoden; %s ist eine Instanzmethode (wie E2376).';
     En: 'static only on class methods; %s is an instance method (like E2376).'),
    (De: 'static nur an nicht virtuellen Klassenmethoden; %s ist virtuell (wie E2376).';
     En: 'static only on non-virtual class methods; %s is virtual (like E2376).'),
    (De: 'Eine Klasse ist entweder abstract oder sealed, nicht beides (wie E2383).';
     En: 'A class is either abstract or sealed, not both (like E2383).'),
    (De: '%s ist abstract, die Klasse %s aber sealed; abstract und sealed schließen sich aus (wie E2383).';
     En: '%s is abstract, but the class %s is sealed; abstract and sealed exclude each other (like E2383).'),
    (De: '%s ist sealed und implementiert die abstrakte Methode %s.%s nicht (wie E2539).';
     En: '%s is sealed and does not implement the abstract method %s.%s (like E2539).'),
    (De: '%s hat abstrakte Methoden und kann deshalb nicht sealed sein; kein Nachfahre könnte sie implementieren ' +
      '(wie E2540).';
     En: '%s has abstract methods and therefore cannot be sealed; no descendant could implement them (like E2540).'),
    (De: '%s ist abstract und kann deshalb nicht sealed sein (wie E2540).';
     En: '%s is abstract and therefore cannot be sealed (like E2540).'),
    (De: 'Rumpf entfernen'; En: 'Remove body'),
    (De: '%s.%s ist abstract und darf keinen Rumpf haben (wie E2136).';
     En: '%s.%s is abstract and must not have a body (like E2136).'));

{$SCOPEDENUMS OFF}

type
  /// <summary>Methodendeklaration einer Klasse: abstrakt oder nicht, mit Zweig der bedingten Übersetzung.</summary>
  TDeclaredMethod = record
    ClassName: string;
    Name: string;
    IsAbstract: Boolean;
    Path: string;
  end;

/// <summary>Typname ohne Typparameter ("TListe&lt;T&gt;" wird "TListe").</summary>
function WithoutTypeParams(const AName: string): string;
begin
  Result := AName;
  if Pos('<', Result) > 0 then
  begin
    Result := Copy(Result, 1, Pos('<', Result) - 1);
  end;
end;

{ TAbstractDeclarationInvalidRule }

function TAbstractDeclarationInvalidRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(cAbstractDeclarationInvalidRuleId, TRuleSeverity.Error,
    cTexts[TMethodDirectivesText.Title].Text);
end;

type
  /// <summary>Ein Lauf von TAbstractDeclarationInvalidRule über eine Unit: Kontext, Bericht und der gemeinsame
  /// Zustand der Prüfschritte. Check legt ihn an und ruft Run.</summary>
  TAbstractDeclarationInvalidScan = record
  private
    FContext: TRuleContext;
    FReport: IRuleReport;
    FTokens: TArray<TPascalToken>;
    FPaths: TArray<string>;
    FDeclared: TDictionary<string, TArray<TDeclaredMethod>>;
    FLines: TArray<string>;
    FAncestry: TAncestry;
    function TokenRange(AIndex: Integer): TTextRange;
    function DeclaredKey(const AClassName, AName: string): string;
    procedure AddDeclared(const AMethod: TDeclaredMethod);
    function DirectiveToken(AHeader: TSyntaxNode; const ADirective: string): Integer;
    function HasDirective(AHeader: TSyntaxNode; const ADirective: string): Boolean;
    procedure CheckHeader(const AClassName: string; AHeader: TSyntaxNode);
    procedure CheckClassHeader(ABody: TSyntaxNode; out AAbstract, ASealed: Boolean);
    function NameToken(AFrom, AEnd: Integer; const AName: string): Integer;
    procedure ReportOwnAbstract(ABody: TSyntaxNode; const AName: string);
    procedure CheckSealed(ADecl, ABody: TSyntaxNode; AAbstract: Boolean);
    function CheckTypeDecl(ANode: TSyntaxNode): TSyntaxNode;
    procedure PushContainers(APending: TStack<TSyntaxNode>; ANode: TSyntaxNode);
    procedure Visit(ARoot: TSyntaxNode);
    procedure Lookup(const AClassName, AName, APath: string; out AAbstract, AConcrete: Boolean);
    function RemoveBody(ARoutine: TSyntaxNode): TArray<TRuleFix>;
    function QualifiedNameToken(AHeader: TSyntaxNode; const AName: string): Integer;
    function HasBody(ARoutine: TSyntaxNode): Boolean;
    function IsAbstractBody(ARoutine: TSyntaxNode; const AClassName, AName: string): Boolean;
    procedure CheckBody(ARoutine: TSyntaxNode);
    procedure VisitBodies(ANode: TSyntaxNode);
  public
    constructor Create(const AContext: TRuleContext; const AReport: IRuleReport);
    procedure Run;
  end;

{ TAbstractDeclarationInvalidScan }

constructor TAbstractDeclarationInvalidScan.Create(const AContext: TRuleContext; const AReport: IRuleReport);
begin
  FContext := AContext;
  FReport := AReport;
end;

function TAbstractDeclarationInvalidScan.TokenRange(AIndex: Integer): TTextRange;
begin
  Result := TTextRange.Create(FTokens[AIndex].StartPos, FTokens[AIndex].EndPos);
end;

function TAbstractDeclarationInvalidScan.DeclaredKey(const AClassName, AName: string): string;
begin
  Result := UpperCase(AClassName) + '.' + UpperCase(AName);
end;

procedure TAbstractDeclarationInvalidScan.AddDeclared(const AMethod: TDeclaredMethod);
var
  mKey: string;
  mGroup: TArray<TDeclaredMethod>;
begin
  mKey := DeclaredKey(AMethod.ClassName, AMethod.Name);
  if not FDeclared.TryGetValue(mKey, mGroup) then
  begin
    mGroup := nil;
  end;
  FDeclared.AddOrSetValue(mKey, mGroup + [AMethod]);
end;

/// <summary>Token der Direktive ADirective im Kopf AHeader; -1 ohne.</summary>
function TAbstractDeclarationInvalidScan.DirectiveToken(AHeader: TSyntaxNode; const ADirective: string): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to AHeader.ChildCount - 1 do
  begin
    if (AHeader[mIndex].Kind = TSyntaxKind.Directive) and SameText(AHeader[mIndex].Name, ADirective) then
    begin
      Result := TokenFrom(FTokens, AHeader[mIndex].StartOffset);
      if Result < Length(FTokens) then
      begin
        Exit;
      end;
    end;
  end;
  Result := -1;
end;

function TAbstractDeclarationInvalidScan.HasDirective(AHeader: TSyntaxNode; const ADirective: string): Boolean;
begin
  Result := DirectiveToken(AHeader, ADirective) >= 0;
end;

procedure TAbstractDeclarationInvalidScan.CheckHeader(const AClassName: string; AHeader: TSyntaxNode);
var
  mFirst, mAbstract_, mFinal, mStatic: Integer;
  mIsVirtual, mIsClassMethod: Boolean;
  mMethod: TDeclaredMethod;
begin
  mFirst := TokenFrom(FTokens, AHeader.StartOffset);
  if mFirst >= Length(FTokens) then
  begin
    Exit;
  end;
  mIsClassMethod := FTokens[mFirst].IsKeyword('class');
  mIsVirtual := HasDirective(AHeader, 'virtual') or HasDirective(AHeader, 'dynamic') or
    HasDirective(AHeader, 'override') or HasDirective(AHeader, 'message');
  mAbstract_ := DirectiveToken(AHeader, 'abstract');
  mFinal := DirectiveToken(AHeader, 'final');
  mStatic := DirectiveToken(AHeader, 'static');
  if (mAbstract_ >= 0) and not mIsVirtual then
  begin
    FReport.Add(TokenRange(mAbstract_), cTexts[TMethodDirectivesText.AbstractVirtual].Text,
      TRuleConfidence.High, [TRuleFix.Create(cTexts[TMethodDirectivesText.InsertVirtual].Text,
      [TRuleEdit.Create(TTextRange.Create(FTokens[mAbstract_].StartPos, FTokens[mAbstract_].StartPos), 'virtual; ')])]);
  end;
  if (mAbstract_ >= 0) and (mFinal >= 0) then
  begin
    FReport.Add(TokenRange(mFinal), cTexts[TMethodDirectivesText.AbstractFinal].Fmt([AHeader.Name]),
      TRuleConfidence.High);
  end
  else if (mFinal >= 0) and not mIsVirtual then
  begin
    FReport.Add(TokenRange(mFinal), cTexts[TMethodDirectivesText.FinalVirtual].Fmt([AHeader.Name]),
      TRuleConfidence.High);
  end;
  if mStatic >= 0 then
  begin
    if not mIsClassMethod then
    begin
      FReport.Add(TokenRange(mStatic), cTexts[TMethodDirectivesText.StaticInstance].Fmt([AHeader.Name]),
        TRuleConfidence.High);
    end
    else if mIsVirtual or (mAbstract_ >= 0) then
    begin
      FReport.Add(TokenRange(mStatic), cTexts[TMethodDirectivesText.StaticVirtual].Fmt([AHeader.Name]),
        TRuleConfidence.High);
    end;
  end;
  mMethod.ClassName := AClassName;
  mMethod.Name := AHeader.Name;
  mMethod.IsAbstract := mAbstract_ >= 0;
  mMethod.Path := TConditionalBranches.PathAt(FPaths, mFirst);
  AddDeclared(mMethod);
end;

/// <summary>E2383: "class abstract sealed" bzw. "class sealed abstract". ASealed: die Klasse ist sealed,
/// AAbstract: abstract.</summary>
procedure TAbstractDeclarationInvalidScan.CheckClassHeader(ABody: TSyntaxNode; out AAbstract, ASealed: Boolean);
var
  mIndex: Integer;
  mAbstract_, mSealed: Boolean;
begin
  AAbstract := False;
  ASealed := False;
  mIndex := TokenFrom(FTokens, ABody.StartOffset);
  if (mIndex >= Length(FTokens)) or not FTokens[mIndex].IsKeyword('class') then
  begin
    Exit;
  end;
  mAbstract_ := False;
  mSealed := False;
  Inc(mIndex);
  while (mIndex < Length(FTokens)) and (FTokens[mIndex].Kind in [TPascalTokenKind.Identifier,
    TPascalTokenKind.Keyword, TPascalTokenKind.Comment]) do
  begin
    if FTokens[mIndex].Kind <> TPascalTokenKind.Comment then
    begin
      if SameText(FTokens[mIndex].Text, 'abstract') then
      begin
        mAbstract_ := True;
      end
      else if SameText(FTokens[mIndex].Text, 'sealed') then
      begin
        mSealed := True;
      end
      else
      begin
        Break;
      end;
      AAbstract := mAbstract_;
      ASealed := mSealed;
      if mAbstract_ and mSealed then
      begin
        FReport.Add(TokenRange(mIndex), cTexts[TMethodDirectivesText.AbstractSealedTitle].Text, TRuleConfidence.High);
        Exit;
      end;
    end;
    Inc(mIndex);
  end;
end;

/// <summary>Token des Namens AName ab AFrom vor dem Offset AEnd (davor können Attribute stehen); -1 ohne.
/// </summary>
function TAbstractDeclarationInvalidScan.NameToken(AFrom, AEnd: Integer; const AName: string): Integer;
begin
  Result := AFrom;
  while (Result < Length(FTokens)) and (FTokens[Result].Offset < AEnd) do
  begin
    if (FTokens[Result].Kind = TPascalTokenKind.Identifier) and SameText(FTokens[Result].Text, AName) then
    begin
      Exit;
    end;
    Inc(Result);
  end;
  Result := -1;
end;

/// <summary>E2383 an jeder eigenen abstrakten Methode der sealed-Klasse AName.</summary>
procedure TAbstractDeclarationInvalidScan.ReportOwnAbstract(ABody: TSyntaxNode; const AName: string);
var
  mIndex, mAbstract: Integer;
begin
  for mIndex := 0 to ABody.ChildCount - 1 do
  begin
    if ABody[mIndex].Kind = TSyntaxKind.RoutineHeader then
    begin
      mAbstract := DirectiveToken(ABody[mIndex], 'abstract');
      if mAbstract >= 0 then
      begin
        FReport.Add(TokenRange(mAbstract), cTexts[TMethodDirectivesText.AbstractInSealed].Fmt([ABody[mIndex].Name,
          AName]), TRuleConfidence.High);
      end;
    end;
  end;
end;

/// <summary>Klasse sealed (#1380): eigene abstrakte Methoden (E2383 an der Methode), offene abstrakte
/// Methoden je E2539 und an der Klasse E2540; abstract sealed ebenso E2540.</summary>
procedure TAbstractDeclarationInvalidScan.CheckSealed(ADecl, ABody: TSyntaxNode; AAbstract: Boolean);
var
  mName: string;
  mNameToken, mIndex: Integer;
  mLocation: TSymbolLocation;
  mOpen: TArray<TIndexSymbol>;
  mOwners: TArray<string>;
begin
  mName := WithoutTypeParams(ADecl.Name);
  mNameToken := NameToken(TokenFrom(FTokens, ADecl.StartOffset), ABody.StartOffset, mName);
  if mNameToken < 0 then
  begin
    Exit;
  end;
  ReportOwnAbstract(ABody, mName);
  mOpen := nil;
  mOwners := nil;
  if FAncestry.FindClass(mName, mLocation) and (mLocation.FileName = '') then
  begin
    mOpen := FAncestry.OpenAbstractMethods(mLocation, mOwners);
  end;
  for mIndex := 0 to High(mOpen) do
  begin
    FReport.Add(TokenRange(mNameToken), cTexts[TMethodDirectivesText.SealedNotImplemented].Fmt([mName,
      mOwners[mIndex], mOpen[mIndex].Name]), TRuleConfidence.High);
  end;
  if mOpen <> nil then
  begin
    FReport.Add(TokenRange(mNameToken), cTexts[TMethodDirectivesText.SealedWithAbstract].Fmt([mName]),
      TRuleConfidence.High);
  end
  else if AAbstract then
  begin
    FReport.Add(TokenRange(mNameToken), cTexts[TMethodDirectivesText.SealedAbstract].Fmt(
      [mName]), TRuleConfidence.High);
  end;
end;

/// <summary>Prüft die Klasse oder das Objekt der Typdeklaration ANode. Ergebnis ist deren Rumpf, ohne Klasse
/// oder Objekt ANode selbst.</summary>
function TAbstractDeclarationInvalidScan.CheckTypeDecl(ANode: TSyntaxNode): TSyntaxNode;
var
  mIndex: Integer;
  mAbstract, mSealed: Boolean;
begin
  Result := ANode.FindChild(TSyntaxKind.ClassType);
  if Result = nil then
  begin
    Result := ANode.FindChild(TSyntaxKind.ObjectType);
  end;
  if Result = nil then
  begin
    Exit(ANode);
  end;
  mAbstract := False;
  mSealed := False;
  if Result.Kind = TSyntaxKind.ClassType then
  begin
    CheckClassHeader(Result, mAbstract, mSealed);
  end;
  for mIndex := 0 to Result.ChildCount - 1 do
  begin
    if Result[mIndex].Kind = TSyntaxKind.RoutineHeader then
    begin
      CheckHeader(WithoutTypeParams(ANode.Name), Result[mIndex]);
    end;
  end;
  if mSealed then
  begin
    CheckSealed(ANode, Result, mAbstract);
  end;
end;

/// <summary>Nur Deklarationscontainer: Anweisungen und Ausdrücke enthalten keine Typen (#1094).</summary>
procedure TAbstractDeclarationInvalidScan.PushContainers(APending: TStack<TSyntaxNode>; ANode: TSyntaxNode);
var
  mIndex: Integer;
begin
  for mIndex := ANode.ChildCount - 1 downto 0 do
  begin
    if ANode[mIndex].Kind in [TSyntaxKind.InterfaceSection, TSyntaxKind.ImplementationSection,
      TSyntaxKind.TypeSection, TSyntaxKind.TypeDecl, TSyntaxKind.RoutineDecl] then
    begin
      APending.Push(ANode[mIndex]);
    end;
  end;
end;

// Iterativ (tiefe Bäume sprengen den Stapel nicht).
procedure TAbstractDeclarationInvalidScan.Visit(ARoot: TSyntaxNode);
var
  mPending: TStack<TSyntaxNode>;
  mNode: TSyntaxNode;
begin
  mPending := TStack<TSyntaxNode>.Create;
  try
    mPending.Push(ARoot);
    while mPending.Count > 0 do
    begin
      mNode := mPending.Pop;
      if mNode.Kind = TSyntaxKind.TypeDecl then
      begin
        mNode := CheckTypeDecl(mNode);
      end;
      PushContainers(mPending, mNode);
    end;
  finally
    mPending.Free;
  end;
end;

/// <summary>Wird mit dem Rumpf an APath eine nicht abstrakte Deklaration AClassName.AName übersetzt? Und
/// eine abstrakte (AAbstract)?</summary>
procedure TAbstractDeclarationInvalidScan.Lookup(const AClassName, AName, APath: string; out AAbstract,
  AConcrete: Boolean);
var
  mMethod: TDeclaredMethod;
  mGroup: TArray<TDeclaredMethod>;
begin
  AAbstract := False;
  AConcrete := False;
  if not FDeclared.TryGetValue(DeclaredKey(AClassName, AName), mGroup) then
  begin
    Exit;
  end;
  for mMethod in mGroup do
  begin
    if not TConditionalBranches.Exclusive(mMethod.Path, APath) then
    begin
      if mMethod.IsAbstract then
      begin
        AAbstract := True;
      end
      else
      begin
        AConcrete := True;
      end;
    end;
  end;
end;

/// <summary>Korrektur: den Rumpf mit seinen Zeilen und einer folgenden Leerzeile entfernen.</summary>
function TAbstractDeclarationInvalidScan.RemoveBody(ARoutine: TSyntaxNode): TArray<TRuleFix>;
var
  mStartPos, mEndPos: TTextPosition;
begin
  Result := nil;
  mStartPos := ARoutine.StartPos;
  mEndPos := ARoutine.EndPos;
  if (mStartPos.Line >= Length(FLines)) or (mEndPos.Line >= Length(FLines)) or
    (Trim(Copy(FLines[mStartPos.Line], 1, mStartPos.Character)) <> '') or
    (Trim(Copy(FLines[mEndPos.Line], mEndPos.Character + 1, MaxInt)) <> '') then
  begin
    Exit;
  end;
  mStartPos.Character := 0;
  mEndPos.Line := mEndPos.Line + 1;
  mEndPos.Character := 0;
  if (mEndPos.Line < Length(FLines)) and (Trim(FLines[mEndPos.Line]) = '') and (mStartPos.Line > 0) and
    (Trim(FLines[mStartPos.Line - 1]) = '') then
  begin
    mEndPos.Line := mEndPos.Line + 1;
  end;
  Result := [TRuleFix.Create(cTexts[TMethodDirectivesText.RemoveBody].Text,
    [TRuleEdit.Create(TTextRange.Create(mStartPos, mEndPos), '')])];
end;

/// <summary>Token des Methodennamens AName hinter dem Klassennamen im Kopf AHeader; -1 ohne.</summary>
function TAbstractDeclarationInvalidScan.QualifiedNameToken(AHeader: TSyntaxNode; const AName: string): Integer;
begin
  Result := TokenFrom(FTokens, AHeader.StartOffset);
  while (Result < Length(FTokens)) and (FTokens[Result].Offset < AHeader.EndOffset) do
  begin
    if (Result > 0) and FTokens[Result - 1].IsSymbol('.') and
      (FTokens[Result].Kind = TPascalTokenKind.Identifier) and SameText(FTokens[Result].Text, AName) then
    begin
      Exit;
    end;
    Inc(Result);
  end;
  Result := -1;
end;

/// <summary>Hat ARoutine einen Rumpf (Block oder asm)?</summary>
function TAbstractDeclarationInvalidScan.HasBody(ARoutine: TSyntaxNode): Boolean;
begin
  Result := (ARoutine.FindChild(TSyntaxKind.Block) <> nil) or (ARoutine.FindChild(TSyntaxKind.AsmBlock) <> nil);
end;

/// <summary>Gehört der Rumpf ARoutine zu einer abstrakten Methode AClassName.AName, und keine gleichnamige
/// nicht abstrakte wird mit ihm übersetzt?</summary>
function TAbstractDeclarationInvalidScan.IsAbstractBody(ARoutine: TSyntaxNode; const AClassName,
  AName: string): Boolean;
var
  mAbstract, mConcrete: Boolean;
begin
  Lookup(AClassName, AName, TConditionalBranches.PathAt(FPaths, TokenFrom(FTokens, ARoutine.StartOffset)), mAbstract,
    mConcrete);
  Result := mAbstract and not mConcrete;
end;

procedure TAbstractDeclarationInvalidScan.CheckBody(ARoutine: TSyntaxNode);
var
  mParts: TArray<string>;
  mClassName, mName: string;
  mHeader: TSyntaxNode;
  mFirst: Integer;
begin
  mParts := ARoutine.Name.Split(['.']);
  if not HasBody(ARoutine) or (Length(mParts) < 2) then
  begin
    Exit;
  end;
  mClassName := mParts[High(mParts) - 1];
  mName := mParts[High(mParts)];
  mHeader := ARoutine.FindChild(TSyntaxKind.RoutineHeader);
  if (mHeader = nil) or not IsAbstractBody(ARoutine, mClassName, mName) then
  begin
    Exit;
  end;
  // Den Namen hinter dem Klassennamen markieren.
  mFirst := QualifiedNameToken(mHeader, mName);
  if mFirst >= 0 then
  begin
    FReport.Add(TokenRange(mFirst), cTexts[TMethodDirectivesText.AbstractBody].Fmt(
      [mClassName, mName]), TRuleConfidence.High, RemoveBody(ARoutine));
  end;
end;

// Rekursion nur in den implementation-Abschnitt (höchstens zwei Ebenen, unabhängig von der Ausdruckstiefe).
procedure TAbstractDeclarationInvalidScan.VisitBodies(ANode: TSyntaxNode);
var
  mIndex: Integer;
begin
  for mIndex := 0 to ANode.ChildCount - 1 do
  begin
    if ANode[mIndex].Kind = TSyntaxKind.RoutineDecl then
    begin
      CheckBody(ANode[mIndex]);
    end
    else if ANode[mIndex].Kind = TSyntaxKind.ImplementationSection then
    begin
      VisitBodies(ANode[mIndex]);
    end;
  end;
end;

procedure TAbstractDeclarationInvalidScan.Run;
var
  mCache: IRuleDerivedCache;
begin
  if (FContext.Tree = nil) or (FContext.Tree.Root = nil) then
  begin
    Exit;
  end;
  FTokens := FContext.Tree.Tokens;
  FPaths := TConditionalBranches.Paths(FTokens);
  FLines := TTextLines.SplitLines(FContext.Text);
  mCache := TRuleDerived.Open(FContext);
  FDeclared := TDictionary<string, TArray<TDeclaredMethod>>.Create;
  try
    FAncestry := TAncestry.Create(FContext.Index, TRuleDerived.UnitIndex(mCache, FContext));
    try
      Visit(FContext.Tree.Root);
    finally
      FAncestry.Free;
    end;
    if FDeclared.Count > 0 then
    begin
      VisitBodies(FContext.Tree.Root);
    end;
  finally
    FDeclared.Free;
  end;
end;

procedure TAbstractDeclarationInvalidRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mScan: TAbstractDeclarationInvalidScan;
begin
  mScan := TAbstractDeclarationInvalidScan.Create(AContext, AReport);
  mScan.Run;
end;

procedure RegisterMethodDirectiveRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TAbstractDeclarationInvalidRule.Create);
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.MethodDirectives', cTexts);

end.
