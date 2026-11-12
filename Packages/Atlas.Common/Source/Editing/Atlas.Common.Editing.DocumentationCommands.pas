unit Atlas.Common.Editing.DocumentationCommands;

// Schnellbefehle für Dokumentation und Markierungen (#306) im Rahmen aus #293:
//   /header           Dateikopf aus slashCommands.headerTemplate setzen bzw. das Jahr
//                     im vorhandenen Kopf fortschreiben
//   /deprecated Grund deprecated 'Grund' an die Deklaration darunter (bei Methoden
//                     an die in der Klasse) und <remarks>Veraltet: Grund</remarks>
//   /region-all       Methoden der Klasse in der implementation nach Gruppen in
//                     {$REGION}-Blöcke ordnen
// /bookmark entfällt laut Ergänzung vom 09.10.: Die IDE und Atlas haben eigene Lesezeichen. Vorhandene
// Kommentare "// @bookmark Name" findet die Symbolsuche weiter (Editing.Bookmarks).

interface

uses
  Atlas.Common.Editing.Contract;

const
  /// <summary>Vorlage, wenn weder slashCommands.headerTemplate noch die Regel file-header eine vorgibt.</summary>
  cDefaultHeaderTemplate = '{ {unit}' + #13#10 + '  Copyright (c) {jahr} {autor} }';

/// <summary>Trägt /header, /deprecated und /region-all über ARegister ein.</summary>
procedure RegisterDocumentationCommands(const ARegister: TSlashRegister);

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Math,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Index.Contract,
  Atlas.Common.Editing.CommandSource,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TDocumentationCommandsText = (HeaderOnlyAppliesInA, DeprecatedBelongsAboveARoutine, TheDeclarationIsAlreadyMarked,
    DeclarationOfNotFound, DeclarationOfIsIncomplete, TypeDeclarationIsIncomplete, HasTooFewMethodsFor,
    TheMethodsOfAreAlready, RegionAllBelongsInThe, ArrangeTheMethodsOfThe, SetTheFileHeaderOr,
    MarkTheDeclarationBelowAs, DeprecatedReason);

const
  cTexts: array[TDocumentationCommandsText] of TAtlasText = (
    (De: '/header gilt nur in einer Unit'; En: '/header only applies in a unit'),
    (De: '/deprecated gehört über eine Routine oder einen Typ'; En: '/deprecated belongs above a routine or a type'),
    (De: 'Die Deklaration ist schon als deprecated markiert'; En: 'The declaration is already marked as deprecated'),
    (De: 'Deklaration von %s nicht gefunden'; En: 'Declaration of %s not found'),
    (De: 'Deklaration von %s ist unvollständig'; En: 'Declaration of %s is incomplete'),
    (De: 'Typdeklaration ist unvollständig'; En: 'Type declaration is incomplete'),
    (De: '%s hat zu wenige Methoden für Regionen'; En: '%s has too few methods for regions'),
    (De: 'Die Methoden von %s stehen schon in Regionen'; En: 'The methods of %s are already in regions'),
    (De: '/region-all gehört in die Deklaration der Klasse';
     En: '/region-all belongs in the declaration of the class'),
    (De: 'Methoden der Klasse in Regionen ordnen'; En: 'Arrange the methods of the class in regions'),
    (De: 'Dateikopf setzen bzw. Jahr fortschreiben'; En: 'Set the file header or update the year'),
    (De: 'Deklaration darunter als veraltet markieren'; En: 'Mark the declaration below as deprecated'),
    (De: '/deprecated Grund'; En: '/deprecated Reason'));

{$SCOPEDENUMS OFF}

type
  TTokens = TArray<TPascalToken>;

const
  cRoutineKeywords: array[0..5] of string = ('procedure', 'function', 'constructor', 'destructor', 'operator',
    'class');
  cDirectives: array[0..29] of string = ('abstract', 'assembler', 'cdecl', 'deprecated', 'dispid', 'dynamic',
    'experimental', 'export', 'external', 'far', 'final', 'forward', 'inline', 'library', 'local', 'message',
    'near', 'overload', 'override', 'pascal', 'platform', 'register', 'reintroduce', 'safecall', 'static',
    'stdcall', 'unsafe', 'varargs', 'virtual', 'winapi');

function IsCode(const AToken: TPascalToken): Boolean;
begin
  Result := not (AToken.Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]);
end;

function NextCode(const ATokens: TTokens; AIndex: Integer): Integer;
begin
  Result := AIndex + 1;
  while (Result <= High(ATokens)) and not IsCode(ATokens[Result]) do
  begin
    Inc(Result);
  end;
end;

function PrevCode(const ATokens: TTokens; AIndex: Integer): Integer;
begin
  Result := AIndex - 1;
  while (Result >= 0) and not IsCode(ATokens[Result]) do
  begin
    Dec(Result);
  end;
end;

function Before(const A, B: TTextPosition): Boolean;
begin
  Result := (A.Line < B.Line) or ((A.Line = B.Line) and (A.Character < B.Character));
end;

{ /header }

/// <summary>Vorlage mit ersetzten Platzhaltern, Zeilenenden wie ALineBreak.</summary>
function ExpandHeader(const ATemplate, AUnitName, ALineBreak: string): string;
var
  mAuthor: string;
begin
  mAuthor := GetEnvironmentVariable('USERNAME');
  if mAuthor = '' then
  begin
    mAuthor := GetEnvironmentVariable('USER');
  end;
  Result := StringReplace(ATemplate, '{unit}', AUnitName, [rfReplaceAll, rfIgnoreCase]);
  Result := StringReplace(Result, '{jahr}', IntToStr(CurrentYear), [rfReplaceAll, rfIgnoreCase]);
  Result := StringReplace(Result, '{autor}', mAuthor, [rfReplaceAll, rfIgnoreCase]);
  Result := StringReplace(StringReplace(Result, #13#10, #10, [rfReplaceAll]), #10, ALineBreak, [rfReplaceAll]);
end;

/// <summary>Ziffer an AIndex (False außerhalb von AText).</summary>
function IsDigitAt(const AText: string; AIndex: Integer): Boolean;
begin
  Result := (AIndex >= 1) and (AIndex <= Length(AText)) and CharInSet(AText[AIndex], ['0'..'9']);
end;

/// <summary>Beginnt an AIndex ein Jahrhundert 19 oder 20 (bzw. 10, 29)?</summary>
function StartsCentury(const AText: string; AIndex: Integer): Boolean;
begin
  Result := CharInSet(AText[AIndex], ['1', '2']) and CharInSet(AText[AIndex + 1], ['0', '9']);
end;

/// <summary>Steht an AIndex eine vierstellige Jahreszahl, die nicht Teil einer längeren Zahl ist?</summary>
function IsYearAt(const AText: string; AIndex: Integer): Boolean;
begin
  Result := StartsCentury(AText, AIndex) and IsDigitAt(AText, AIndex + 2) and IsDigitAt(AText, AIndex + 3) and
    not IsDigitAt(AText, AIndex - 1) and not IsDigitAt(AText, AIndex + 4);
end;

/// <summary>Letzte Jahreszahl (19xx/20xx) in AText ab 1; 0 ohne.</summary>
function LastYear(const AText: string; out AYear: Integer): Integer;
var
  mIndex: Integer;
begin
  Result := 0;
  AYear := 0;
  for mIndex := 1 to Length(AText) - 3 do
  begin
    if IsYearAt(AText, mIndex) then
    begin
      Result := mIndex;
      AYear := StrToInt(Copy(AText, mIndex, 4));
    end;
  end;
end;

/// <summary>Erstes Token, das kein Kommentar und keine Direktive ist; hinter dem Ende ohne.</summary>
function FirstCode(const ATokens: TTokens): Integer;
begin
  Result := 0;
  while (Result <= High(ATokens)) and not IsCode(ATokens[Result]) do
  begin
    Inc(Result);
  end;
end;

/// <summary>Steht vor AFirst ein Kommentar (der vorhandene Dateikopf)?</summary>
function HasHeaderComment(const ATokens: TTokens; AFirst: Integer): Boolean;
var
  mIndex: Integer;
begin
  Result := False;
  for mIndex := 0 to AFirst - 1 do
  begin
    Result := Result or (ATokens[mIndex].Kind = TPascalTokenKind.Comment);
  end;
end;

/// <summary>AText mit dem laufenden Jahr an der Jahreszahl ab AYearPos: 2019 wird 2019-2026, 2019-2025 wird
/// 2019-2026.</summary>
function WithCurrentYear(const AText: string; AYearPos: Integer): string;
begin
  if (AYearPos > 1) and (AText[AYearPos - 1] = '-') then
  begin
    Result := Copy(AText, 1, AYearPos - 1) + IntToStr(CurrentYear) + Copy(AText, AYearPos + 4, MaxInt);
  end
  else
  begin
    Result := Copy(AText, 1, AYearPos + 3) + '-' + IntToStr(CurrentYear) + Copy(AText, AYearPos + 4, MaxInt);
  end;
end;

/// <summary>Fortgeschriebenes Jahr im Kommentar mit der letzten Jahreszahl vor AFirst; leer, wenn es aktuell ist
/// oder fehlt.</summary>
function YearEdits(const ATokens: TTokens; AFirst: Integer): TArray<TTextEdit>;
var
  mIndex, mLast, mYear, mYearPos: Integer;
begin
  Result := nil;
  mLast := -1;
  for mIndex := 0 to AFirst - 1 do
  begin
    if (ATokens[mIndex].Kind = TPascalTokenKind.Comment) and (LastYear(ATokens[mIndex].Text, mYear) > 0) then
    begin
      mLast := mIndex;
    end;
  end;
  if mLast < 0 then
  begin
    Exit;
  end;
  mYearPos := LastYear(ATokens[mLast].Text, mYear);
  if mYear < CurrentYear then
  begin
    Result := [TTextEdit.Create(TTextRange.Create(ATokens[mLast].StartPos, ATokens[mLast].EndPos),
      WithCurrentYear(ATokens[mLast].Text, mYearPos))];
  end;
end;

/// <summary>Neuer Dateikopf aus der Vorlage des Hosts bzw. DefaultHeaderTemplate.</summary>
function NewHeader(ASource: TCommandSource; const AContext: TSlashContext): TArray<TTextEdit>;
var
  mTemplate, mHeader: string;
begin
  mTemplate := '';
  if AContext.Host <> nil then
  begin
    mTemplate := AContext.Host.HeaderTemplate(AContext.Uri);
  end;
  if mTemplate = '' then
  begin
    mTemplate := cDefaultHeaderTemplate;
  end;
  mHeader := ExpandHeader(mTemplate, ASource.Tree.Root.Name, ASource.LineBreak) + ASource.LineBreak;
  if ASource.Line = 0 then
  begin
    Result := [TTextEdit.Create(TTextRange.Create(0, 0, 1, 0), mHeader)];
  end
  else
  begin
    Result := [TTextEdit.Create(TTextRange.Create(0, 0, 0, 0), mHeader), ASource.RemoveCommand];
  end;
end;

function ExecuteHeader(const AContext: TSlashContext; out AEdits: TArray<TTextEdit>; out AReason: string): Boolean;
var
  mSource: TCommandSource;
  mTokens: TTokens;
  mFirst: Integer;
begin
  AEdits := nil;
  mSource := TCommandSource.Create(AContext);
  try
    mTokens := mSource.Tree.Tokens;
    mFirst := FirstCode(mTokens);
    if (mFirst > High(mTokens)) or (mSource.Tree.Root = nil) or (mSource.Tree.Root.Name = '') then
    begin
      Exit(Fail(cTexts[TDocumentationCommandsText.HeaderOnlyAppliesInA].Text, AReason));
    end;
    // Kommentare vor "unit" bilden den vorhandenen Kopf; dort nur das Jahr fortschreiben.
    if HasHeaderComment(mTokens, mFirst) then
    begin
      AEdits := YearEdits(mTokens, mFirst);
      AEdits := AEdits + [mSource.RemoveCommand];
    end
    else
    begin
      AEdits := NewHeader(mSource, AContext);
    end;
    Result := True;
  finally
    mSource.Free;
  end;
end;

{ /deprecated }

/// <summary>Index des ";" auf Klammertiefe 0 ab AStart; -1 ohne.</summary>
function StatementEnd(const ATokens: TTokens; AStart: Integer): Integer;
var
  mDepth: Integer;
begin
  mDepth := 0;
  Result := AStart;
  while (Result <= High(ATokens)) and ((mDepth <> 0) or not ATokens[Result].IsSymbol(';')) do
  begin
    if ATokens[Result].IsSymbol('(') or ATokens[Result].IsSymbol('[') then
    begin
      Inc(mDepth);
    end
    else if ATokens[Result].IsSymbol(')') or ATokens[Result].IsSymbol(']') then
    begin
      Dec(mDepth);
    end;
    Inc(Result);
  end;
  if Result > High(ATokens) then
  begin
    Result := -1;
  end;
end;

/// <summary>Index des nächsten Symbols ASymbol ab AStart; hinter dem Ende ohne.</summary>
function NextSymbol(const ATokens: TTokens; AStart: Integer; const ASymbol: string): Integer;
begin
  Result := AStart;
  while (Result <= High(ATokens)) and not ATokens[Result].IsSymbol(ASymbol) do
  begin
    Inc(Result);
  end;
end;

/// <summary>Token-Index des abschließenden ";" der Routinendeklaration ab AStart samt Direktiven.</summary>
function RoutineEnd(const ATokens: TTokens; AStart: Integer; out ADeprecated: Boolean): Integer;
var
  mNext, mStop: Integer;
begin
  ADeprecated := False;
  Result := StatementEnd(ATokens, AStart);
  if Result < 0 then
  begin
    Exit;
  end;
  mNext := NextCode(ATokens, Result);
  mStop := Result;
  while (mStop <= High(ATokens)) and (mNext <= High(ATokens)) and MatchText(ATokens[mNext].Text, cDirectives) do
  begin
    ADeprecated := ADeprecated or SameText(ATokens[mNext].Text, 'deprecated');
    mStop := NextSymbol(ATokens, mNext, ';');
    if mStop <= High(ATokens) then
    begin
      Result := mStop;
      mNext := NextCode(ATokens, Result);
    end;
  end;
end;

/// <summary>Erstes Token einer Routinendeklaration in Zeile ALine; -1 ohne.</summary>
function RoutineTokenAt(const ATokens: TTokens; ALine: Integer): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(ATokens) do
  begin
    if (ATokens[mIndex].StartPos.Line = ALine) and MatchText(ATokens[mIndex].Text, cRoutineKeywords) then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

/// <summary>Name hinter procedure/function usw. ab AStart, mit Punkten.</summary>
function RoutineName(const ATokens: TTokens; AStart: Integer): string;
var
  mIndex: Integer;
begin
  mIndex := AStart;
  while (mIndex <= High(ATokens)) and MatchText(ATokens[mIndex].Text, cRoutineKeywords) do
  begin
    mIndex := NextCode(ATokens, mIndex);
  end;
  Result := '';
  while mIndex <= High(ATokens) do
  begin
    Result := Result + ATokens[mIndex].Text;
    mIndex := NextCode(ATokens, mIndex);
    if (mIndex > High(ATokens)) or not ATokens[mIndex].IsSymbol('.') then
    begin
      Break;
    end;
    Result := Result + '.';
    mIndex := NextCode(ATokens, mIndex);
  end;
end;

/// <summary>Methode, Konstruktor oder Routine AName in AContainer?</summary>
function IsRoutineSymbol(const ASymbol: TIndexSymbol; const AName, AContainer: string): Boolean;
begin
  Result := (ASymbol.Kind in [TIndexSymbolKind.Method, TIndexSymbolKind.Constructor_, TIndexSymbolKind.Routine]) and
    SameText(ASymbol.Name, AName) and SameText(ASymbol.Container, AContainer);
end;

/// <summary>Zeile der Deklaration zu einer Implementierung (Methode in der Klasse, Routine im interface);
/// -1, wenn die Routine nur hier steht.</summary>
function DeclarationLine(ASource: TCommandSource; const AName: string; AImplLine: Integer): Integer;
var
  mSymbol: TIndexSymbol;
  mContainer, mName: string;
  mDot: Integer;
begin
  mDot := LastDelimiter('.', AName);
  mContainer := Copy(AName, 1, mDot - 1);
  if LastDelimiter('.', mContainer) > 0 then
  begin
    mContainer := Copy(mContainer, LastDelimiter('.', mContainer) + 1, MaxInt);
  end;
  mName := Copy(AName, mDot + 1, MaxInt);
  for mSymbol in ASource.UnitIndex.Symbols do
  begin
    if IsRoutineSymbol(mSymbol, mName, mContainer) and (mSymbol.Range.StartPos.Line < AImplLine) and
      ((mContainer <> '') or mSymbol.InInterface) then
    begin
      Exit(mSymbol.Range.StartPos.Line);
    end;
  end;
  Result := -1;
end;

function FindTypeDecl(ANode: TSyntaxNode; ALine: Integer): TSyntaxNode;
var
  mRoot: TSyntaxNode;
  mLine: Integer;
begin
  mRoot := ANode;
  mLine := ALine;
  // Search statt Rekursion; unter ANode nur Knoten, die ALine überdecken.
  Result := ANode.Search(
    function(ACandidate: TSyntaxNode): TSyntaxSearchStep
    begin
      if (ACandidate <> mRoot) and ((ACandidate.StartPos.Line > mLine) or (ACandidate.EndPos.Line < mLine)) then
      begin
        Exit(TSyntaxSearchStep.Skip);
      end;
      Result := TSyntaxSearchStep.Descend;
      if (ACandidate.Kind = TSyntaxKind.TypeDecl) and (ACandidate.StartPos.Line = mLine) then
      begin
        Result := TSyntaxSearchStep.Found;
      end;
    end);
end;

/// <summary>Erstes Code-Token unter Zeile ALine hinter Attributen [..]; -1 ohne.</summary>
function TargetBelow(const ATokens: TTokens; ALine: Integer): Integer;
begin
  Result := 0;
  while (Result <= High(ATokens)) and ((ATokens[Result].StartPos.Line <= ALine) or not IsCode(ATokens[Result])) do
  begin
    Inc(Result);
  end;
  while (Result <= High(ATokens)) and ATokens[Result].IsSymbol('[') do
  begin
    Result := NextCode(ATokens, NextSymbol(ATokens, Result, ']'));
  end;
  if Result > High(ATokens) then
  begin
    Result := -1;
  end;
end;

/// <summary>Letztes ";" ab AFrom, das vor AEnd endet; -1 ohne.</summary>
function LastSemicolonBefore(const ATokens: TTokens; AFrom: Integer; const AEnd: TTextPosition): Integer;
var
  mIndex: Integer;
begin
  Result := -1;
  mIndex := AFrom;
  while (mIndex <= High(ATokens)) and not Before(AEnd, ATokens[mIndex].EndPos) do
  begin
    if ATokens[mIndex].IsSymbol(';') then
    begin
      Result := mIndex;
    end;
    Inc(mIndex);
  end;
end;

/// <summary>Steht vor AStop schon "deprecated" bzw. "deprecated 'Grund'"?</summary>
function DeprecatedBefore(const ATokens: TTokens; AStop: Integer): Boolean;
var
  mPrev: Integer;
begin
  mPrev := PrevCode(ATokens, AStop);
  if (mPrev >= 0) and (ATokens[mPrev].Kind = TPascalTokenKind.StringLiteral) then
  begin
    mPrev := PrevCode(ATokens, mPrev);
  end;
  Result := (mPrev >= 0) and SameText(ATokens[mPrev].Text, 'deprecated');
end;

type
  /// <summary>Wo die Direktive deprecated hinkommt: an die Routinendeklaration oder vor das ";" des Typs.</summary>
  TDeprecationPlan = record
    Tokens: TTokens;
    /// <summary>Erstes Token der Deklaration.</summary>
    Target: Integer;
    Hint: string;
    Directive: TTextEdit;
    Present: Boolean;
    Error: string;
    function Plan(ASource: TCommandSource): Boolean;
    function PlanRoutine(ASource: TCommandSource): Boolean;
    function PlanType(ASource: TCommandSource): Boolean;
  end;

function TDeprecationPlan.Plan(ASource: TCommandSource): Boolean;
begin
  Error := cTexts[TDocumentationCommandsText.DeprecatedBelongsAboveARoutine].Text;
  Result := Target >= 0;
  if Result and MatchText(Tokens[Target].Text, cRoutineKeywords) then
  begin
    Result := PlanRoutine(ASource);
  end
  else if Result then
  begin
    Result := PlanType(ASource);
  end;
  if Result and Present then
  begin
    Error := cTexts[TDocumentationCommandsText.TheDeclarationIsAlreadyMarked].Text;
    Result := False;
  end;
end;

function TDeprecationPlan.PlanRoutine(ASource: TCommandSource): Boolean;
var
  mName: string;
  mDeclLine, mStop: Integer;
begin
  mName := RoutineName(Tokens, Target);
  mDeclLine := DeclarationLine(ASource, mName, Tokens[Target].StartPos.Line);
  // Die Direktive steht nur an der Deklaration, nie an der Implementierung.
  if mDeclLine >= 0 then
  begin
    Target := RoutineTokenAt(Tokens, mDeclLine);
  end;
  mStop := -1;
  if Target >= 0 then
  begin
    mStop := RoutineEnd(Tokens, Target, Present);
  end;
  Result := mStop >= 0;
  if Target < 0 then
  begin
    Error := cTexts[TDocumentationCommandsText.DeclarationOfNotFound].Fmt([mName]);
  end
  else if mStop < 0 then
  begin
    Error := cTexts[TDocumentationCommandsText.DeclarationOfIsIncomplete].Fmt([mName]);
  end
  else
  begin
    Directive := TTextEdit.Create(TTextRange.Create(Tokens[mStop].EndPos, Tokens[mStop].EndPos), Hint + ';');
  end;
end;

function TDeprecationPlan.PlanType(ASource: TCommandSource): Boolean;
var
  mTypeNode: TSyntaxNode;
  mStop: Integer;
begin
  mTypeNode := FindTypeDecl(ASource.Tree.Root, Tokens[Target].StartPos.Line);
  mStop := -1;
  if mTypeNode <> nil then
  begin
    mStop := LastSemicolonBefore(Tokens, Target, mTypeNode.EndPos);
  end;
  Result := mStop >= 0;
  if (mTypeNode <> nil) and (mStop < 0) then
  begin
    Error := cTexts[TDocumentationCommandsText.TypeDeclarationIsIncomplete].Text;
  end
  else if Result then
  begin
    Present := DeprecatedBefore(Tokens, mStop);
    Directive := TTextEdit.Create(TTextRange.Create(Tokens[mStop].StartPos, Tokens[mStop].StartPos), Hint);
  end;
end;

/// <summary>" deprecated" bzw. " deprecated 'Grund'".</summary>
function DeprecationHint(const AReason: string): string;
begin
  Result := ' deprecated';
  if AReason <> '' then
  begin
    Result := Result + ' ' + QuotedStr(AReason);
  end;
end;

/// <summary>Zeile "/// &lt;remarks&gt;Veraltet: Grund&lt;/remarks&gt;" mit Einrückung und Zeilenende.</summary>
function RemarkLine(ASource: TCommandSource; ALine: Integer; const AReason: string): string;
begin
  Result := ASource.Indent(ALine) + '/// <remarks>Veraltet';
  if AReason <> '' then
  begin
    Result := Result + ': ' + AReason;
  end;
  Result := Result + '</remarks>' + ASource.LineBreak;
end;

function ExecuteDeprecated(const AContext: TSlashContext; out AEdits: TArray<TTextEdit>;
  out AReason: string): Boolean;
var
  mSource: TCommandSource;
  mPlan: TDeprecationPlan;
  mDeclLine: Integer;
  mRemark: string;
begin
  AEdits := nil;
  mSource := TCommandSource.Create(AContext);
  try
    mPlan := Default(TDeprecationPlan);
    mPlan.Tokens := mSource.Tree.Tokens;
    mPlan.Target := TargetBelow(mPlan.Tokens, mSource.Line);
    mPlan.Hint := DeprecationHint(AContext.Arguments);
    if not mPlan.Plan(mSource) then
    begin
      Exit(Fail(mPlan.Error, AReason));
    end;
    mDeclLine := mPlan.Tokens[mPlan.Target].StartPos.Line;
    mRemark := RemarkLine(mSource, mDeclLine, AContext.Arguments);
    if mDeclLine = mSource.Line + 1 then
    begin
      AEdits := [TTextEdit.Create(TTextRange.Create(mSource.Line, 0, mSource.Line + 1, 0), mRemark),
        mPlan.Directive];
    end
    else
    begin
      AEdits := [TTextEdit.Create(TTextRange.Create(mDeclLine, 0, mDeclLine, 0), mRemark), mPlan.Directive,
        mSource.RemoveCommand];
    end;
    Result := True;
  finally
    mSource.Free;
  end;
end;

{ /region-all }

type
  TBody = record
    Name: string;
    FirstLine: Integer;
    LastLine: Integer;
    Group: Integer;
  end;

  TBodies = TArray<TBody>;

const
  cGroupNames: array[0..5] of string = ('Ereignis-Handler', 'Published', 'Public', 'Protected', 'Private',
    'Getter und Setter');

/// <summary>Die ersten drei Zeilen der Routine, für die Erkennung von Ereignis-Handlern.</summary>
function RoutineHeaderText(ASource: TCommandSource; ARoutine: TSyntaxNode): string;
var
  mIndex: Integer;
begin
  Result := '';
  for mIndex := ARoutine.StartPos.Line to Min(ARoutine.StartPos.Line + 2, High(ASource.Lines)) do
  begin
    Result := Result + ASource.Lines[mIndex];
  end;
end;

/// <summary>GetXyz bzw. SetXyz.</summary>
function IsAccessorName(const AName: string): Boolean;
begin
  Result := (Length(AName) > 3) and (StartsText('Get', AName) or StartsText('Set', AName)) and
    CharInSet(AName[4], ['A'..'Z']);
end;

function VisibilityGroup(AVisibility: TIndexVisibility): Integer;
begin
  case AVisibility of
    TIndexVisibility.Published:
      Result := 1;
    TIndexVisibility.Public:
      Result := 2;
    TIndexVisibility.Protected, TIndexVisibility.StrictProtected:
      Result := 3;
  else
    Result := 4;
  end;
end;

/// <summary>Gruppe nach der Sichtbarkeit der Deklaration AName in AClass; Private, wenn sie fehlt.</summary>
function MemberGroup(ASource: TCommandSource; const AClass: TIndexSymbol; const AName: string): Integer;
var
  mSymbol: TIndexSymbol;
begin
  for mSymbol in ASource.UnitIndex.Symbols do
  begin
    if SameText(mSymbol.Name, AName) and SameText(mSymbol.Container, AClass.Name) and
      (mSymbol.Range.StartPos.Line > AClass.Range.StartPos.Line) and
      (mSymbol.Range.EndPos.Line <= AClass.Range.EndPos.Line) then
    begin
      Exit(VisibilityGroup(mSymbol.Visibility));
    end;
  end;
  Result := 4;
end;

function GroupOf(ASource: TCommandSource; const AClass: TIndexSymbol; ARoutine: TSyntaxNode): Integer;
var
  mName: string;
begin
  mName := Copy(ARoutine.Name, LastDelimiter('.', ARoutine.Name) + 1, MaxInt);
  if ContainsText(RoutineHeaderText(ASource, ARoutine), 'Sender: TObject') then
  begin
    Result := 0;
  end
  else if IsAccessorName(mName) then
  begin
    Result := 5;
  end
  else
  begin
    Result := MemberGroup(ASource, AClass, mName);
  end;
end;

/// <summary>Methode der Klasse AClassName selbst (keine einer inneren Klasse).</summary>
function IsMethodOf(ANode: TSyntaxNode; const AClassName: string): Boolean;
begin
  Result := (ANode.Kind = TSyntaxKind.RoutineDecl) and StartsText(AClassName + '.', ANode.Name) and
    (Pos('.', Copy(ANode.Name, Length(AClassName) + 2, MaxInt)) = 0);
end;

/// <summary>Kommentarzeile ("//" oder "{", aber keine Direktive "{$").</summary>
function IsCommentLine(const ALine: string): Boolean;
var
  mText: string;
begin
  mText := TrimLeft(ALine);
  Result := StartsStr('//', mText) or (StartsStr('{', mText) and not StartsText('{$', mText));
end;

/// <summary>Erste Zeile der Methode an ANode samt der Kommentare direkt darüber (ohne die Befehlszeile).</summary>
function BodyStart(ASource: TCommandSource; ANode: TSyntaxNode): Integer;
begin
  Result := ANode.StartPos.Line;
  while (Result > 0) and (Result - 1 <> ASource.Line) and IsCommentLine(ASource.Lines[Result - 1]) do
  begin
    Dec(Result);
  end;
end;

/// <summary>Methodenrümpfe der Klasse in der implementation, in Textreihenfolge.</summary>
function ClassBodies(ASource: TCommandSource; const AClass: TIndexSymbol): TBodies;
var
  mSection: TSyntaxNode;
  mIndex: Integer;
  mBody: TBody;
begin
  Result := nil;
  mSection := ASource.Tree.Root.FindChild(TSyntaxKind.ImplementationSection);
  if mSection = nil then
  begin
    Exit;
  end;
  for mIndex := 0 to mSection.ChildCount - 1 do
  begin
    if IsMethodOf(mSection[mIndex], AClass.Name) then
    begin
      mBody.Name := mSection[mIndex].Name;
      mBody.FirstLine := BodyStart(ASource, mSection[mIndex]);
      mBody.LastLine := mSection[mIndex].EndPos.Line;
      mBody.Group := GroupOf(ASource, AClass, mSection[mIndex]);
      Result := Result + [mBody];
    end;
  end;
end;

/// <summary>Steht zwischen der ersten und der letzten Methode schon ein {$REGION}?</summary>
function HasRegions(ASource: TCommandSource; const ABodies: TBodies): Boolean;
var
  mLine: Integer;
begin
  Result := False;
  for mLine := ABodies[0].FirstLine to ABodies[High(ABodies)].LastLine do
  begin
    Result := Result or StartsText('{$REGION', TrimLeft(ASource.Lines[mLine]));
  end;
end;

/// <summary>Steht der Befehl in einer der Methoden?</summary>
function CommandInBodies(ASource: TCommandSource; const ABodies: TBodies): Boolean;
var
  mBody: TBody;
begin
  Result := False;
  for mBody in ABodies do
  begin
    Result := Result or ((ASource.Line >= mBody.FirstLine) and (ASource.Line <= mBody.LastLine));
  end;
end;

/// <summary>Grund, warum die Methoden nicht in Regionen geordnet werden; '' wenn es geht.</summary>
function RegionError(ASource: TCommandSource; const AClassName: string; const ABodies: TBodies): string;
begin
  Result := '';
  if Length(ABodies) < 2 then
  begin
    Result := cTexts[TDocumentationCommandsText.HasTooFewMethodsFor].Fmt([AClassName]);
  end
  else if HasRegions(ASource, ABodies) then
  begin
    Result := cTexts[TDocumentationCommandsText.TheMethodsOfAreAlready].Fmt([AClassName]);
  end
  else if CommandInBodies(ASource, ABodies) then
  begin
    Result := cTexts[TDocumentationCommandsText.RegionAllBelongsInThe].Text;
  end;
end;

/// <summary>Zeilen aller Methoden der Gruppe AGroup, durch Leerzeilen getrennt; '' ohne.</summary>
function GroupBlock(ASource: TCommandSource; const ABodies: TBodies; AGroup: Integer): string;
var
  mBody: TBody;
  mLine: Integer;
begin
  Result := '';
  for mBody in ABodies do
  begin
    if mBody.Group <> AGroup then
    begin
      Continue;
    end;
    if Result <> '' then
    begin
      Result := Result + ASource.LineBreak;
    end;
    for mLine := mBody.FirstLine to mBody.LastLine do
    begin
      Result := Result + ASource.Lines[mLine] + ASource.LineBreak;
    end;
  end;
end;

/// <summary>Alle Gruppen als {$REGION}-Blöcke, durch Leerzeilen getrennt.</summary>
function RegionText(ASource: TCommandSource; const ABodies: TBodies): string;
var
  mGroup: Integer;
  mBlock: string;
begin
  Result := '';
  for mGroup := 0 to High(cGroupNames) do
  begin
    mBlock := GroupBlock(ASource, ABodies, mGroup);
    if mBlock = '' then
    begin
      Continue;
    end;
    if Result <> '' then
    begin
      Result := Result + ASource.LineBreak;
    end;
    Result := Result + Format('{$REGION ''%s''}', [cGroupNames[mGroup]]) + ASource.LineBreak + mBlock +
      '{$ENDREGION}' + ASource.LineBreak;
  end;
end;

/// <summary>Erste Methode wird durch ARegions ersetzt, die übrigen entfallen samt Leerzeile danach.</summary>
function RegionEdits(ASource: TCommandSource; const ABodies: TBodies; const ARegions: string): TArray<TTextEdit>;
var
  mIndex, mStop: Integer;
begin
  Result := [TTextEdit.Create(TTextRange.Create(ABodies[0].FirstLine, 0, ABodies[0].LastLine + 1, 0), ARegions)];
  for mIndex := 1 to High(ABodies) do
  begin
    mStop := ABodies[mIndex].LastLine + 1;
    if (mStop <= High(ASource.Lines)) and (Trim(ASource.Lines[mStop]) = '') and (mStop <> ASource.Line) then
    begin
      Inc(mStop);
    end;
    Result := Result + [TTextEdit.Create(TTextRange.Create(ABodies[mIndex].FirstLine, 0, mStop, 0), '')];
  end;
end;

function ExecuteRegionAll(const AContext: TSlashContext; out AEdits: TArray<TTextEdit>;
  out AReason: string): Boolean;
var
  mSource: TCommandSource;
  mClass: TIndexSymbol;
  mBodies: TBodies;
  mError: string;
begin
  AEdits := nil;
  mSource := TCommandSource.Create(AContext);
  try
    mBodies := nil;
    mError := cTexts[TDocumentationCommandsText.RegionAllBelongsInThe].Text;
    if mSource.ClassAt(mClass) then
    begin
      mBodies := ClassBodies(mSource, mClass);
      mError := RegionError(mSource, mClass.Name, mBodies);
    end;
    if mError <> '' then
    begin
      Exit(Fail(mError, AReason));
    end;
    AEdits := RegionEdits(mSource, mBodies, RegionText(mSource, mBodies));
    AEdits := AEdits + [mSource.RemoveCommand];
    Result := True;
  finally
    mSource.Free;
  end;
end;

function Command(const AName, ASummary, AExample: string; const AExecute: TSlashExecute): TSlashCommand;
begin
  Result.Name := AName;
  Result.Summary := ASummary;
  Result.Example := AExample;
  Result.Execute := AExecute;
end;

procedure RegisterDocumentationCommands(const ARegister: TSlashRegister);
begin
  ARegister(Command('header', cTexts[TDocumentationCommandsText.SetTheFileHeaderOr].Text, '/header', ExecuteHeader));
  ARegister(Command('deprecated', cTexts[TDocumentationCommandsText.MarkTheDeclarationBelowAs].Text,
    cTexts[TDocumentationCommandsText.DeprecatedReason].Text,
    ExecuteDeprecated));
  ARegister(Command('region-all', cTexts[TDocumentationCommandsText.ArrangeTheMethodsOfThe].Text, '/region-all',
    ExecuteRegionAll));
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Editing.DocumentationCommands', cTexts);

end.
