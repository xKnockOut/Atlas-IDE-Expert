unit Atlas.Common.Lsp.CompletionSyntax;

// Hinweis bei unvollständigem Code (#457, ARG-059): Wie sicher ist der Kontext der Vervollständigung?
// - Sicher, wenn vor dem Cursor in der aktuellen Routine bzw. Klassendeklaration kein Syntaxfehler steht.
//   Eingeschränkt sonst, mit Zeile und Text des ersten Fehlers; unbekannt, wenn es dann keine Einträge gibt.
// - Die Routine bzw. Klasse bestimmen die Tokens, nicht der Baum: Fehlt in einer früheren Methode ein end, hängt
//   der fehlertolerante Parser die folgenden Methoden in sie hinein, und ihre Fehlermeldung steht in der nächsten.
//   Grenzen sind deshalb Zeilen, die mit dem Routinenkopf in Spalte 0 beginnen (procedure, function, constructor,
//   destructor, operator, auch nach class) bzw. mit einer Typdeklaration "TFoo = class|record|interface|object"
//   in Spalte 0 bis 2, dazu die Abschnitte (interface, implementation, initialization, finalization, end.).
//   In einer Klasse beenden auch type, var, const, resourcestring, threadvar und uses den Bereich.
// - Der Bereich wird für sich geparst (in eine leere Unit gestellt, Zeilen bleiben an ihrer Stelle). Nur Fehler
//   davon zählen, und nur die vor dem getippten Wort: Was gerade entsteht, ist immer unvollständig.
// - Meldungen der Prüfungen am fertigen Baum (TreeIntact) zählen nicht; der Baum ist dort heil.

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree;

type
  {$SCOPEDENUMS ON}
  TCompletionTrust = (Sure, Limited, Unknown);
  TCompletionScopeKind = (None, Routine, TypeDecl);
  {$SCOPEDENUMS OFF}

  /// <summary>Vertrauensstatus einer Antwort samt erstem Fehler (Zeile und Spalte ab 0; -1 ohne).</summary>
  TCompletionSyntaxNotice = record
    Trust: TCompletionTrust;
    Line: Integer;
    Character: Integer;
    Message: string;
  end;

  /// <summary>Bereich der Routine bzw. Klassendeklaration um den Cursor: Zeilen FirstLine bis LastLine.</summary>
  TCompletionScope = record
    Kind: TCompletionScopeKind;
    FirstLine: Integer;
    LastLine: Integer;
  end;

  TCompletionSyntax = class
  public const
    /// <summary>Kopf bzw. Ende der leeren Unit, in die der Bereich gestellt wird.</summary>
    RoutineHead = 'unit AtlasScope; implementation';
    TypeHead = 'unit AtlasScope; interface type';
    RoutineTail = 'end.';
    TypeTail = 'implementation end.';
  public
    /// <summary>Bereich um APosition; Kind None außerhalb einer Routine bzw. Klassendeklaration.</summary>
    class function ScopeAt(const ATokens: TArray<TPascalToken>; const APosition: TTextPosition): TCompletionScope;
      static;
    /// <summary>Text, in dem nur die Zeilen von AScope stehen, eingebettet in eine leere Unit.</summary>
    class function ScopeText(const AText: string; const AScope: TCompletionScope): string; static;
    /// <summary>Beginn des Worts, das an APosition getippt wird (Bezeichnerzeichen davor).</summary>
    class function WordStart(const AText: string; const APosition: TTextPosition): TTextPosition; static;
    /// <summary>Status für den Cursor APosition in AText mit dem Baum ATree; ACount: Zahl der Einträge.</summary>
    class function Assess(ATree: TSyntaxTree; const AText: string; const APosition: TTextPosition;
      ACount: Integer): TCompletionSyntaxNotice; static;
    /// <summary>"sure", "limited", "unknown".</summary>
    class function TrustName(ATrust: TCompletionTrust): string; static;
    /// <summary>Trägt "syntaxNotice" in die CompletionList ein; nichts bei Sure.</summary>
    class procedure WriteJson(AList: TJSONObject; const ANotice: TCompletionSyntaxNotice); static;
  end;

implementation

uses
  Atlas.Common.Pascal.TreeCache,
  System.Generics.Collections,
  Atlas.Common.Pascal.Parser;

type
  {$SCOPEDENUMS ON}
  TAnchorKind = (Routine, TypeDecl, Section, Local);
  {$SCOPEDENUMS OFF}

  TAnchor = record
    Kind: TAnchorKind;
    Line: Integer;
    /// <summary>Bei Local: begin (zählt einmal je Routine).</summary>
    IsBegin: Boolean;
  end;

function IsTrivia(const AToken: TPascalToken): Boolean;
begin
  Result := AToken.Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive];
end;

function IsWord(const AToken: TPascalToken; const AWord: string): Boolean;
begin
  Result := (AToken.Kind in [TPascalTokenKind.Identifier, TPascalTokenKind.Keyword]) and SameText(AToken.Text, AWord);
end;

function IsRoutineWord(const AToken: TPascalToken): Boolean;
begin
  Result := IsWord(AToken, 'procedure') or IsWord(AToken, 'function') or IsWord(AToken, 'constructor') or
    IsWord(AToken, 'destructor') or IsWord(AToken, 'operator');
end;

function NextSignificant(const ATokens: TArray<TPascalToken>; AIndex: Integer): Integer;
begin
  Result := AIndex + 1;
  while (Result <= High(ATokens)) and IsTrivia(ATokens[Result]) do
    Inc(Result);
end;

/// <summary>"TFoo = [packed] class|record|interface|dispinterface|object" ab ATokens[AIndex], nicht "class of"
/// und keine Vorwärtsdeklaration "class;".</summary>
function StartsTypeDecl(const ATokens: TArray<TPascalToken>; AIndex: Integer): Boolean;
var
  Index: Integer;
begin
  Result := False;
  if ATokens[AIndex].Kind <> TPascalTokenKind.Identifier then
    Exit;
  Index := NextSignificant(ATokens, AIndex);
  // Generische Parameter überspringen: TFoo<T> = class.
  if (Index <= High(ATokens)) and ATokens[Index].IsSymbol('<') then
    while (Index <= High(ATokens)) and not ATokens[Index].IsSymbol('>') do
      Index := NextSignificant(ATokens, Index);
  if (Index <= High(ATokens)) and ATokens[Index].IsSymbol('>') then
    Index := NextSignificant(ATokens, Index);
  if (Index > High(ATokens)) or not ATokens[Index].IsSymbol('=') then
    Exit;
  Index := NextSignificant(ATokens, Index);
  if (Index <= High(ATokens)) and IsWord(ATokens[Index], 'packed') then
    Index := NextSignificant(ATokens, Index);
  if Index > High(ATokens) then
    Exit;
  if IsWord(ATokens[Index], 'class') then
  begin
    Index := NextSignificant(ATokens, Index);
    Result := (Index > High(ATokens)) or not (IsWord(ATokens[Index], 'of') or ATokens[Index].IsSymbol(';'));
  end
  else
    Result := IsWord(ATokens[Index], 'record') or IsWord(ATokens[Index], 'interface') or
      IsWord(ATokens[Index], 'dispinterface') or IsWord(ATokens[Index], 'object');
end;

function Anchors(const ATokens: TArray<TPascalToken>): TArray<TAnchor>;
var
  List: TList<TAnchor>;
  Index, Next, LastLine: Integer;
  Anchor: TAnchor;
  Token: TPascalToken;
begin
  List := TList<TAnchor>.Create;
  try
    LastLine := -1;
    for Index := 0 to High(ATokens) do
    begin
      Token := ATokens[Index];
      if IsTrivia(Token) then
        Continue;
      // Nur das erste Token einer Zeile.
      if Token.StartPos.Line = LastLine then
        Continue;
      LastLine := Token.StartPos.Line;
      Anchor := Default(TAnchor);
      Anchor.Line := Token.StartPos.Line;
      Next := NextSignificant(ATokens, Index);
      if Token.StartPos.Character = 0 then
      begin
        if IsRoutineWord(Token) or (IsWord(Token, 'class') and (Next <= High(ATokens)) and
          IsRoutineWord(ATokens[Next])) then
          Anchor.Kind := TAnchorKind.Routine
        else if IsWord(Token, 'interface') or IsWord(Token, 'implementation') or
          IsWord(Token, 'initialization') or IsWord(Token, 'finalization') or
          (IsWord(Token, 'end') and (Next <= High(ATokens)) and ATokens[Next].IsSymbol('.')) then
          Anchor.Kind := TAnchorKind.Section
        else if IsWord(Token, 'type') or IsWord(Token, 'var') or IsWord(Token, 'const') or
          IsWord(Token, 'resourcestring') or IsWord(Token, 'threadvar') or IsWord(Token, 'uses') or
          IsWord(Token, 'label') or IsWord(Token, 'begin') then
        begin
          Anchor.Kind := TAnchorKind.Local;
          Anchor.IsBegin := IsWord(Token, 'begin');
        end
        else if StartsTypeDecl(ATokens, Index) then
          Anchor.Kind := TAnchorKind.TypeDecl
        else
          Continue;
      end
      else if (Token.StartPos.Character <= 2) and StartsTypeDecl(ATokens, Index) then
        Anchor.Kind := TAnchorKind.TypeDecl
      else
        Continue;
      List.Add(Anchor);
    end;
    Result := List.ToArray;
  finally
    List.Free;
  end;
end;

{ TCompletionSyntax }

class function TCompletionSyntax.ScopeAt(const ATokens: TArray<TPascalToken>;
  const APosition: TTextPosition): TCompletionScope;
var
  List: TArray<TAnchor>;
  Index, Start, Last: Integer;
  SawBegin: Boolean;
begin
  Result := Default(TCompletionScope);
  Result.FirstLine := -1;
  Result.LastLine := -1;
  List := Anchors(ATokens);
  // Letzter Anker bis zur Zeile des Cursors; in einer Routine über ihre var-, const- und begin-Zeilen zurück.
  Start := -1;
  for Index := 0 to High(List) do
    if List[Index].Line <= APosition.Line then
      Start := Index;
  SawBegin := False;
  while (Start >= 0) and (List[Start].Kind = TAnchorKind.Local) do
  begin
    // Zwei begin in Spalte 0: Das untere ist der Hauptblock eines Programms.
    if List[Start].IsBegin then
    begin
      if SawBegin then
        Exit;
      SawBegin := True;
    end;
    Dec(Start);
    if (Start >= 0) and (List[Start].Kind <> TAnchorKind.Local) and (List[Start].Kind <> TAnchorKind.Routine) then
      Exit;
  end;
  if (Start < 0) or (List[Start].Kind = TAnchorKind.Section) then
    Exit;
  // Eine Klasse endet an type/var/const …, die Routine nur am nächsten Kopf, Typ oder Abschnitt.
  Last := MaxInt;
  for Index := Start + 1 to High(List) do
    if (List[Index].Line > List[Start].Line) and
      ((List[Index].Kind <> TAnchorKind.Local) or (List[Start].Kind = TAnchorKind.TypeDecl)) then
    begin
      Last := List[Index].Line - 1;
      Break;
    end;
  if List[Start].Kind = TAnchorKind.Routine then
    Result.Kind := TCompletionScopeKind.Routine
  else
    Result.Kind := TCompletionScopeKind.TypeDecl;
  Result.FirstLine := List[Start].Line;
  Result.LastLine := Last;
end;

class function TCompletionSyntax.ScopeText(const AText: string; const AScope: TCompletionScope): string;
var
  Lines: TArray<string>;
  Builder: TStringBuilder;
  Index: Integer;
begin
  Lines := AText.Split([#10]);
  Builder := TStringBuilder.Create;
  try
    if AScope.Kind = TCompletionScopeKind.Routine then
      Builder.Append(RoutineHead)
    else
      Builder.Append(TypeHead);
    // Zeilen davor leer, damit Positionen gleich bleiben; Zeile 0 trägt den Kopf.
    for Index := 1 to High(Lines) do
    begin
      Builder.Append(#10);
      if (Index >= AScope.FirstLine) and (Index <= AScope.LastLine) then
        Builder.Append(Lines[Index].TrimRight([#13]));
    end;
    Builder.Append(#10);
    if AScope.Kind = TCompletionScopeKind.Routine then
      Builder.Append(RoutineTail)
    else
      Builder.Append(TypeTail);
    Result := Builder.ToString;
  finally
    Builder.Free;
  end;
end;

class function TCompletionSyntax.WordStart(const AText: string; const APosition: TTextPosition): TTextPosition;
var
  Lines: TArray<string>;
  Line: string;
  Character: Integer;
begin
  Result := APosition;
  Lines := AText.Split([#10]);
  if (APosition.Line < 0) or (APosition.Line > High(Lines)) then
    Exit;
  Line := Lines[APosition.Line];
  Character := APosition.Character;
  if Character > Length(Line) then
    Character := Length(Line);
  while (Character > 0) and CharInSet(Line[Character], ['A'..'Z', 'a'..'z', '0'..'9', '_', '&']) do
    Dec(Character);
  Result := TTextPosition.Create(APosition.Line, Character);
end;

function Before(const A, B: TTextPosition): Boolean;
begin
  Result := (A.Line < B.Line) or ((A.Line = B.Line) and (A.Character < B.Character));
end;

class function TCompletionSyntax.Assess(ATree: TSyntaxTree; const AText: string; const APosition: TTextPosition;
  ACount: Integer): TCompletionSyntaxNotice;
var
  Diagnostic: TSyntaxDiagnostic;
  Broken: Boolean;
  Scope: TCompletionScope;
  Tree: TSyntaxTree;
  Limit: TTextPosition;
begin
  Result := Default(TCompletionSyntaxNotice);
  Result.Line := -1;
  Result.Character := -1;
  if ATree = nil then
    Exit;
  // Ohne Fehler im ganzen Baum keine eigene Prüfung.
  Broken := False;
  for Diagnostic in ATree.Diagnostics do
    if not Diagnostic.TreeIntact then
      Broken := True;
  if not Broken then
    Exit;
  Scope := ScopeAt(ATree.Tokens, APosition);
  if (Scope.Kind = TCompletionScopeKind.None) or (Scope.FirstLine < 1) then
    Exit;
  Limit := WordStart(AText, APosition);
  Tree := TSyntaxTreeCache.Parse(ScopeText(AText, Scope));
  try
    for Diagnostic in Tree.Diagnostics do
      if not Diagnostic.TreeIntact and (Diagnostic.StartPos.Line >= Scope.FirstLine) and
        Before(Diagnostic.StartPos, Limit) then
      begin
        Result.Line := Diagnostic.StartPos.Line;
        Result.Character := Diagnostic.StartPos.Character;
        Result.Message := Diagnostic.Message;
        if ACount = 0 then
          Result.Trust := TCompletionTrust.Unknown
        else
          Result.Trust := TCompletionTrust.Limited;
        Exit;
      end;
  finally
    Tree.Free;
  end;
end;

class function TCompletionSyntax.TrustName(ATrust: TCompletionTrust): string;
begin
  case ATrust of
    TCompletionTrust.Limited: Result := 'limited';
    TCompletionTrust.Unknown: Result := 'unknown';
  else
    Result := 'sure';
  end;
end;

class procedure TCompletionSyntax.WriteJson(AList: TJSONObject; const ANotice: TCompletionSyntaxNotice);
var
  Notice: TJSONObject;
begin
  if ANotice.Trust = TCompletionTrust.Sure then
    Exit;
  Notice := TJSONObject.Create;
  Notice.AddPair('trust', TrustName(ANotice.Trust));
  Notice.AddPair('line', TJSONNumber.Create(ANotice.Line));
  Notice.AddPair('character', TJSONNumber.Create(ANotice.Character));
  Notice.AddPair('message', ANotice.Message);
  AList.AddPair('syntaxNotice', Notice);
end;

end.
