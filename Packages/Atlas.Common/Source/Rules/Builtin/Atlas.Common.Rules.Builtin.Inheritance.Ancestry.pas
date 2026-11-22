unit Atlas.Common.Rules.Builtin.Inheritance.Ancestry;

// Gemeinsame Hilfen der Vererbungsregeln (Atlas.Common.Rules.Builtin.Inheritance und ihre Teilunits): Methoden
// der Datei, Korrekturen für Direktiven und Anweisungen. Die Vorfahren selbst löst TAncestry
// (Atlas.Common.Semantics.Ancestry) auf.

interface

uses
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Semantics.Ancestry;

type
  /// <summary>Bereich ganzer Zeilen als Offsets ab 0: Anfang und Ende samt Zeilenumbruch.</summary>
  TLineSpan = record
    Start: Integer;
    Finish: Integer;
  end;

/// <summary>Token am Offset AOffset; False ohne.</summary>
function TokenAt(const AContext: TRuleContext; AOffset: Integer; out AToken: TPascalToken): Boolean;
/// <summary>Korrektur, die " ADirective;" hinter den Methodenkopf setzt.</summary>
function AppendDirective(const AContext: TRuleContext; const AMethod: TMethodDecl; const ADirective: string;
  out AFix: TRuleFix): Boolean;
/// <summary>Erweitert [AStart, AEnd) (Offsets ab 0) auf ganze Zeilen samt Zeilenumbruch, wenn davor und dahinter
/// auf der Zeile nur Leerraum steht; sonst False. ADocComments: darüberstehende ///-Zeilen gehören dazu.
/// ABlankAfter: Steht über dem Bereich eine Leerzeile, fällt auch eine Leerzeile dahinter weg.</summary>
function WholeLineSpan(const AText: string; AStart, AEnd: Integer; ADocComments, ABlankAfter: Boolean;
  out ASpan: TLineSpan): Boolean;
/// <summary>Korrektur, die die Anweisung AStatement samt Semikolon entfernt, allein auf der Zeile die ganze Zeile.
/// </summary>
function RemoveStatementFix(const ACache: IRuleDerivedCache; const AContext: TRuleContext; AStatement: TSyntaxNode;
  const ATitle: string): TRuleFix;
/// <summary>Methodendeklarationen aller Klassen der Datei.</summary>
function ClassMethods(const AContext: TRuleContext; AAncestry: TAncestry): TArray<TMethodDecl>;
/// <summary>destructor Destroy ohne Parameter?</summary>
function IsDestroy(const AMethod: TMethodDecl): Boolean;
/// <summary>constructor Create(AOwner: TComponent)?</summary>
function IsComponentCreate(const AMethod: TMethodDecl): Boolean;
/// <summary>Wird das Verdecken bereits bewusst angezeigt oder gelöst?</summary>
function Settled(const AMethod: TMethodDecl): Boolean;
/// <summary>Methoden der Datei ohne override/reintroduce; False ohne Syntaxbaum.
/// AAncestry gehört dem Aufrufer.</summary>
function Prepare(const AContext: TRuleContext; out AAncestry: TAncestry; out AMethods: TArray<TMethodDecl>): Boolean;

implementation

uses
  Atlas.Common.Rules.Derived,
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Localization.Texts,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Text.Names;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Befundmeldungen in beiden Sprachen (#1458).</summary>
  TInheritanceAncestryText = (AddName);

const
  cTexts: array[TInheritanceAncestryText] of TAtlasText = (
    (De: '"%s" ergänzen'; En: 'Add "%s"'));

{$SCOPEDENUMS OFF}

{ Hilfen für die Regeln }

function TokenAt(const AContext: TRuleContext; AOffset: Integer; out AToken: TPascalToken): Boolean;
var
  mToken: TPascalToken;
begin
  for mToken in AContext.Tree.Tokens do
  begin
    if mToken.Offset = AOffset then
    begin
      AToken := mToken;
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Position hinter dem letzten Token vor AEndOffset.</summary>
function EndPosition(const AContext: TRuleContext; AEndOffset: Integer; out APosition: TTextPosition): Boolean;
var
  mToken: TPascalToken;
begin
  Result := False;
  for mToken in AContext.Tree.Tokens do
  begin
    if mToken.Offset >= AEndOffset then
    begin
      Break;
    end;
    if mToken.Offset + Length(mToken.Text) = AEndOffset then
    begin
      APosition := mToken.EndPos;
      Result := True;
    end;
  end;
end;

/// <summary>Korrektur, die " ADirective;" hinter den Methodenkopf setzt.</summary>
function AppendDirective(const AContext: TRuleContext; const AMethod: TMethodDecl; const ADirective: string;
  out AFix: TRuleFix): Boolean;
var
  mPosition: TTextPosition;
begin
  Result := EndPosition(AContext, AMethod.Header.EndOffset, mPosition);
  if Result then
  begin
    AFix := TRuleFix.Create(cTexts[TInheritanceAncestryText.AddName].Fmt([ADirective]),
      [TRuleEdit.Create(TTextRange.Create(mPosition, mPosition), ' ' + ADirective + ';')]);
  end;
end;

/// <summary>Anfang der Zeile vor der Zeile, die bei AOffset beginnt; AContent ist ihr Text.</summary>
function PreviousLine(const AText: string; AOffset: Integer; out AContent: string): Integer;
var
  mEnd: Integer;
begin
  mEnd := AOffset - 1;
  if (mEnd > 0) and (AText[mEnd] = #13) then
  begin
    Dec(mEnd);
  end;
  Result := mEnd;
  while (Result > 0) and not CharInSet(AText[Result], [#10, #13]) do
  begin
    Dec(Result);
  end;
  AContent := Copy(AText, Result + 1, mEnd - Result);
end;

/// <summary>Ende der Zeile, die bei AOffset beginnt, samt Zeilenumbruch; AContent ist ihr Text.</summary>
function LineEndFrom(const AText: string; AOffset: Integer; out AContent: string): Integer;
begin
  Result := AOffset;
  while (Result < Length(AText)) and not CharInSet(AText[Result + 1], [#10, #13]) do
  begin
    Inc(Result);
  end;
  AContent := Copy(AText, AOffset + 1, Result - AOffset);
  if (Result < Length(AText)) and (AText[Result + 1] = #13) then
  begin
    Inc(Result);
  end;
  if (Result < Length(AText)) and (AText[Result + 1] = #10) then
  begin
    Inc(Result);
  end;
end;

/// <summary>Steht vor AStart und hinter AEnd auf der Zeile nur Leerraum? Dann ist ASpan von der Zeile bis vor den
/// Zeilenumbruch hinter AEnd erweitert.</summary>
function OwnLine(const AText: string; AStart, AEnd: Integer; out ASpan: TLineSpan): Boolean;
begin
  ASpan.Start := AStart;
  while (ASpan.Start > 0) and CharInSet(AText[ASpan.Start], [' ', #9]) do
  begin
    Dec(ASpan.Start);
  end;
  ASpan.Finish := AEnd;
  while (ASpan.Finish < Length(AText)) and CharInSet(AText[ASpan.Finish + 1], [' ', #9]) do
  begin
    Inc(ASpan.Finish);
  end;
  Result := ((ASpan.Start = 0) or CharInSet(AText[ASpan.Start], [#10, #13])) and
    ((ASpan.Finish >= Length(AText)) or CharInSet(AText[ASpan.Finish + 1], [#10, #13]));
end;

/// <summary>Anfang der ///-Zeilen direkt über der Zeile, die bei AStart beginnt; AStart ohne.</summary>
function DocCommentStart(const AText: string; AStart: Integer): Integer;
var
  mPrevious: Integer;
  mContent: string;
  mDone: Boolean;
begin
  Result := AStart;
  mDone := False;
  while not mDone and (Result > 0) do
  begin
    mPrevious := PreviousLine(AText, Result, mContent);
    mDone := not StartsStr('///', TrimLeft(mContent));
    if not mDone then
    begin
      Result := mPrevious;
    end;
  end;
end;

function WholeLineSpan(const AText: string; AStart, AEnd: Integer; ADocComments, ABlankAfter: Boolean;
  out ASpan: TLineSpan): Boolean;
var
  mNext: Integer;
  mContent: string;
begin
  Result := OwnLine(AText, AStart, AEnd, ASpan);
  if not Result then
  begin
    Exit;
  end;
  ASpan.Finish := LineEndFrom(AText, ASpan.Finish, mContent);
  if ADocComments then
  begin
    ASpan.Start := DocCommentStart(AText, ASpan.Start);
  end;
  // Die Leerzeile hinter dem Rumpf trennte ihn vom Nächsten; sie geht mit.
  if ABlankAfter and (ASpan.Finish < Length(AText)) then
  begin
    mNext := LineEndFrom(AText, ASpan.Finish, mContent);
    if Trim(mContent) = '' then
    begin
      ASpan.Finish := mNext;
    end;
  end;
end;

/// <summary>Korrektur, die die Anweisung AStatement samt Semikolon entfernt, allein auf der Zeile die ganze Zeile.
/// </summary>
function RemoveStatementFix(const ACache: IRuleDerivedCache; const AContext: TRuleContext; AStatement: TSyntaxNode;
  const ATitle: string): TRuleFix;
var
  mText: string;
  mStart, mEnd: Integer;
  mSpan: TLineSpan;
begin
  mText := AContext.Text;
  mStart := AStatement.StartOffset;
  mEnd := AStatement.EndOffset;
  while (mEnd < Length(mText)) and CharInSet(mText[mEnd + 1], [' ', #9]) do
  begin
    Inc(mEnd);
  end;
  if (mEnd < Length(mText)) and (mText[mEnd + 1] = ';') then
  begin
    Inc(mEnd);
  end
  else
  begin
    mEnd := AStatement.EndOffset;
  end;
  if WholeLineSpan(mText, mStart, mEnd, False, False, mSpan) then
  begin
    mStart := mSpan.Start;
    mEnd := mSpan.Finish;
  end;
  Result := TRuleFix.Create(ATitle, [TRuleEdit.Create(TRuleDerived.OffsetRange(ACache, AContext, mStart, mEnd),
    '')]);
end;

/// <summary>Direktiven des Methodenkopfs AHeader, klein geschrieben.</summary>
function DirectivesOf(AHeader: TSyntaxNode): TArray<string>;
var
  mInner: Integer;
begin
  Result := nil;
  for mInner := 0 to AHeader.ChildCount - 1 do
  begin
    if AHeader[mInner].Kind = TSyntaxKind.Directive then
    begin
      Result := Result + [LowerCase(AHeader[mInner].Name)];
    end;
  end;
end;

/// <summary>Methode AHeader der Klasse ATypeDecl mit Schlüsselwort und Direktiven, noch ohne Symbol.</summary>
function NewMethod(const AContext: TRuleContext; ATypeDecl, AHeader: TSyntaxNode): TMethodDecl;
var
  mToken: TPascalToken;
begin
  Result := Default(TMethodDecl);
  Result.ClassName := ATypeDecl.Name;
  Result.Header := AHeader;
  if TokenAt(AContext, AHeader.StartOffset, mToken) then
  begin
    Result.Keyword := LowerCase(mToken.Text);
  end;
  Result.Directives := DirectivesOf(AHeader);
end;

/// <summary>Symbol der Methode AHeader der Klasse ATypeName im Index der Datei; False ohne.</summary>
function MethodSymbol(AAncestry: TAncestry; const ATypeName: string; AHeader: TSyntaxNode;
  out ASymbol: TIndexSymbol): Boolean;
begin
  Result := AAncestry.LocalMethodAt(ATypeName, AHeader.StartPos, ASymbol);
end;

/// <summary>Methodendeklarationen aller Klassen der Datei.</summary>
function ClassMethods(const AContext: TRuleContext; AAncestry: TAncestry): TArray<TMethodDecl>;
const
  // Nur hier stehen Klassendeklarationen. Anweisungen und Ausdrücke bleiben außen vor: Ihre Bäume
  // können sehr tief sein (lange Verkettungen in erzeugten Units), und jede Ebene kostete Stapel.
  cContainers = [TSyntaxKind.UnitFile, TSyntaxKind.ProgramFile, TSyntaxKind.LibraryFile, TSyntaxKind.PackageFile,
    TSyntaxKind.InterfaceSection, TSyntaxKind.ImplementationSection, TSyntaxKind.TypeSection, TSyntaxKind.TypeDecl,
    TSyntaxKind.ClassType, TSyntaxKind.ObjectType, TSyntaxKind.RecordType, TSyntaxKind.HelperType,
    TSyntaxKind.RoutineDecl];
var
  mMethods: TList<TMethodDecl>;

  // Eigene Routine für die großen Records (TIndexSymbol, TMethodDecl, TPascalToken): Sie liegen nur
  // einmal auf dem Stapel, nicht in jeder Ebene von Visit.
  procedure AddMethods(ATypeDecl: TSyntaxNode);
  var
    mIndex: Integer;
    mBody, mHeader: TSyntaxNode;
    mMethod: TMethodDecl;
  begin
    mBody := ATypeDecl.FindChild(TSyntaxKind.ClassType);
    if mBody = nil then
    begin
      Exit;
    end;
    for mIndex := 0 to mBody.ChildCount - 1 do
    begin
      mHeader := mBody[mIndex];
      if mHeader.Kind <> TSyntaxKind.RoutineHeader then
      begin
        Continue;
      end;
      mMethod := NewMethod(AContext, ATypeDecl, mHeader);
      // class procedure/static: keine virtuellen Instanzmethoden.
      if (mMethod.Keyword <> 'class') and not mMethod.Has('static') and not mMethod.Has('message') and
        MethodSymbol(AAncestry, ATypeDecl.Name, mHeader, mMethod.Symbol) then
      begin
        mMethods.Add(mMethod);
      end;
    end;
  end;

  procedure Visit(ARoot: TSyntaxNode);
  var
    mIndex: Integer;
    mNode: TSyntaxNode;
    mPending: TStack<TSyntaxNode>;
  begin
    // Iterativ (tiefe Bäume sprengen den Stapel nicht).
    mPending := TStack<TSyntaxNode>.Create;
    try
      mPending.Push(ARoot);
      while mPending.Count > 0 do
      begin
        mNode := mPending.Pop;
        if mNode.Kind = TSyntaxKind.TypeDecl then
        begin
          AddMethods(mNode);
        end;
        for mIndex := mNode.ChildCount - 1 downto 0 do
        begin
          if mNode[mIndex].Kind in cContainers then
          begin
            mPending.Push(mNode[mIndex]);
          end;
        end;
      end;
    finally
      mPending.Free;
    end;
  end;

begin
  mMethods := TList<TMethodDecl>.Create;
  try
    Visit(AContext.Tree.Root);
    Result := mMethods.ToArray;
  finally
    mMethods.Free;
  end;
end;

function IsDestroy(const AMethod: TMethodDecl): Boolean;
begin
  Result := (AMethod.Keyword = 'destructor') and SameText(AMethod.Symbol.Name, 'Destroy') and
    (AMethod.Symbol.MaxArgs = 0);
end;

function IsComponentCreate(const AMethod: TMethodDecl): Boolean;
begin
  Result := (AMethod.Keyword = 'constructor') and SameText(AMethod.Symbol.Name, 'Create') and
    (Length(AMethod.Symbol.ParamTypes) = 1) and SameText(TTextNames.BareTypeName(AMethod.Symbol.ParamTypes[0]),
      'TComponent');
end;

/// <summary>Wird das Verdecken bereits bewusst angezeigt oder gelöst?</summary>
function Settled(const AMethod: TMethodDecl): Boolean;
begin
  Result := AMethod.Has('override') or AMethod.Has('reintroduce');
end;

/// <summary>Methoden der Datei ohne override/reintroduce; False ohne Syntaxbaum.
/// AAncestry gehört dem Aufrufer.</summary>
function Prepare(const AContext: TRuleContext; out AAncestry: TAncestry; out AMethods: TArray<TMethodDecl>): Boolean;
var
  mMethod: TMethodDecl;
  mCache: IRuleDerivedCache;
begin
  AAncestry := nil;
  AMethods := nil;
  if AContext.Tree = nil then
  begin
    Exit(False);
  end;
  // Den Index der Datei teilt der Lauf mit den anderen Regeln.
  mCache := TRuleDerived.Open(AContext);
  AAncestry := TAncestry.Create(AContext.Index, TRuleDerived.UnitIndex(mCache, AContext));
  for mMethod in ClassMethods(AContext, AAncestry) do
  begin
    if not Settled(mMethod) then
    begin
      AMethods := AMethods + [mMethod];
    end;
  end;
  Result := True;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.Inheritance.Ancestry', cTexts);

end.
