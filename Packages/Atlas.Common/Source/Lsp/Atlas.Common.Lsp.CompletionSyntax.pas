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
  begin
    Inc(Result);
  end;
end;

/// <summary>"TFoo = [packed] class|record|interface|dispinterface|object" ab ATokens[AIndex], nicht "class of"
/// und keine Vorwärtsdeklaration "class;".</summary>
function StartsTypeDecl(const ATokens: TArray<TPascalToken>; AIndex: Integer): Boolean;
var
  Index: Integer;
begin
  Result := False;
  if ATokens[AIndex].Kind <> TPascalTokenKind.Identifier then
  begin
    Exit;
  end;
  Index := NextSignificant(ATokens, AIndex);
  // Generische Parameter überspringen: TFoo<T> = class.
  if (Index <= High(ATokens)) and ATokens[Index].IsSymbol('<') then
  begin
    while (Index <= High(ATokens)) and not ATokens[Index].IsSymbol('>') do
    begin
      Index := NextSignificant(ATokens, Index);
    end;
  end;
  if (Index <= High(ATokens)) and ATokens[Index].IsSymbol('>') then
  begin
    Index := NextSignificant(ATokens, Index);
  end;
  if (Index > High(ATokens)) or not ATokens[Index].IsSymbol('=') then
  begin
    Exit;
  end;
  Index := NextSignificant(ATokens, Index);
  if (Index <= High(ATokens)) and IsWord(ATokens[Index], 'packed') then
  begin
    Index := NextSignificant(ATokens, Index);
  end;
  if Index > High(ATokens) then
  begin
    Exit;
  end;
  if IsWord(ATokens[Index], 'class') then
  begin
    Index := NextSignificant(ATokens, Index);
    Result := (Index > High(ATokens)) or not (IsWord(ATokens[Index], 'of') or ATokens[Index].IsSymbol(';'));
  end
  else
  begin
    Result := IsWord(ATokens[Index], 'record') or IsWord(ATokens[Index], 'interface') or
      IsWord(ATokens[Index], 'dispinterface') or IsWord(ATokens[Index], 'object');
  end;
end;

function IsAnyWord(const AToken: TPascalToken; const AWords: array of string): Boolean;
var
  mWord: string;
begin
  for mWord in AWords do
  begin
    if IsWord(AToken, mWord) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Art des Ankers für das Token AIndex in Spalte 0 in AAnchor; False, wenn es keinen öffnet.</summary>
function ColumnZeroKind(const ATokens: TArray<TPascalToken>; AIndex: Integer; var AAnchor: TAnchor): Boolean;
var
  mToken: TPascalToken;
  mNext: Integer;
  mHasNext: Boolean;
begin
  mToken := ATokens[AIndex];
  mNext := NextSignificant(ATokens, AIndex);
  mHasNext := mNext <= High(ATokens);
  Result := True;
  if IsRoutineWord(mToken) or (IsWord(mToken, 'class') and mHasNext and IsRoutineWord(ATokens[mNext])) then
  begin
    AAnchor.Kind := TAnchorKind.Routine;
  end
  else if IsAnyWord(mToken, ['interface', 'implementation', 'initialization', 'finalization']) or
    (IsWord(mToken, 'end') and mHasNext and ATokens[mNext].IsSymbol('.')) then
  begin
    AAnchor.Kind := TAnchorKind.Section;
  end
  else if IsAnyWord(mToken, ['type', 'var', 'const', 'resourcestring', 'threadvar', 'uses', 'label', 'begin']) then
  begin
    AAnchor.Kind := TAnchorKind.Local;
    AAnchor.IsBegin := IsWord(mToken, 'begin');
  end
  else if StartsTypeDecl(ATokens, AIndex) then
  begin
    AAnchor.Kind := TAnchorKind.TypeDecl;
  end
  else
  begin
    Result := False;
  end;
end;

/// <summary>Anker für das erste Token AIndex einer Zeile; False, wenn dort keiner beginnt.</summary>
function AnchorAt(const ATokens: TArray<TPascalToken>; AIndex: Integer; out AAnchor: TAnchor): Boolean;
begin
  AAnchor := Default(TAnchor);
  AAnchor.Line := ATokens[AIndex].StartPos.Line;
  if ATokens[AIndex].StartPos.Character = 0 then
  begin
    Result := ColumnZeroKind(ATokens, AIndex, AAnchor);
  end
  else
  begin
    Result := (ATokens[AIndex].StartPos.Character <= 2) and StartsTypeDecl(ATokens, AIndex);
    if Result then
    begin
      AAnchor.Kind := TAnchorKind.TypeDecl;
    end;
  end;
end;

function Anchors(const ATokens: TArray<TPascalToken>): TArray<TAnchor>;
var
  mList: TList<TAnchor>;
  mIndex, mLastLine: Integer;
  mAnchor: TAnchor;
begin
  mList := TList<TAnchor>.Create;
  try
    mLastLine := -1;
    for mIndex := 0 to High(ATokens) do
    begin
      // Nur das erste Token einer Zeile.
      if IsTrivia(ATokens[mIndex]) or (ATokens[mIndex].StartPos.Line = mLastLine) then
      begin
        Continue;
      end;
      mLastLine := ATokens[mIndex].StartPos.Line;
      if AnchorAt(ATokens, mIndex, mAnchor) then
      begin
        mList.Add(mAnchor);
      end;
    end;
    Result := mList.ToArray;
  finally
    mList.Free;
  end;
end;

/// <summary>Letzter Anker bis Zeile ALine; -1 ohne.</summary>
function LastAnchorUpTo(const AList: TArray<TAnchor>; ALine: Integer): Integer;
var
  mIndex: Integer;
begin
  Result := -1;
  for mIndex := 0 to High(AList) do
  begin
    if AList[mIndex].Line <= ALine then
    begin
      Result := mIndex;
    end;
  end;
end;

/// <summary>Anker, der den Bereich an Zeile ALine öffnet: in einer Routine über ihre var-, const- und
/// begin-Zeilen zurück. -1 ohne (Abschnitt, Hauptblock eines Programms).</summary>
function OpeningAnchor(const AList: TArray<TAnchor>; ALine: Integer): Integer;
var
  mSawBegin: Boolean;
begin
  Result := LastAnchorUpTo(AList, ALine);
  mSawBegin := False;
  while (Result >= 0) and (AList[Result].Kind = TAnchorKind.Local) do
  begin
    // Zwei begin in Spalte 0: Das untere ist der Hauptblock eines Programms.
    if AList[Result].IsBegin then
    begin
      if mSawBegin then
      begin
        Exit(-1);
      end;
      mSawBegin := True;
    end;
    Dec(Result);
    if (Result >= 0) and not (AList[Result].Kind in [TAnchorKind.Local, TAnchorKind.Routine]) then
    begin
      Exit(-1);
    end;
  end;
  if (Result >= 0) and (AList[Result].Kind = TAnchorKind.Section) then
  begin
    Result := -1;
  end;
end;

/// <summary>Letzte Zeile des Bereichs ab Anker AStart: Eine Klasse endet an type/var/const …, die Routine nur am
/// nächsten Kopf, Typ oder Abschnitt.</summary>
function ScopeEnd(const AList: TArray<TAnchor>; AStart: Integer): Integer;
var
  mIndex: Integer;
begin
  Result := MaxInt;
  for mIndex := AStart + 1 to High(AList) do
  begin
    if (AList[mIndex].Line > AList[AStart].Line) and
      ((AList[mIndex].Kind <> TAnchorKind.Local) or (AList[AStart].Kind = TAnchorKind.TypeDecl)) then
    begin
      Exit(AList[mIndex].Line - 1);
    end;
  end;
end;

{ TCompletionSyntax }

class function TCompletionSyntax.ScopeAt(const ATokens: TArray<TPascalToken>;
  const APosition: TTextPosition): TCompletionScope;
var
  mList: TArray<TAnchor>;
  mStart: Integer;
begin
  Result := Default(TCompletionScope);
  Result.FirstLine := -1;
  Result.LastLine := -1;
  mList := Anchors(ATokens);
  mStart := OpeningAnchor(mList, APosition.Line);
  if mStart < 0 then
  begin
    Exit;
  end;
  if mList[mStart].Kind = TAnchorKind.Routine then
  begin
    Result.Kind := TCompletionScopeKind.Routine;
  end
  else
  begin
    Result.Kind := TCompletionScopeKind.TypeDecl;
  end;
  Result.FirstLine := mList[mStart].Line;
  Result.LastLine := ScopeEnd(mList, mStart);
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
    begin
      Builder.Append(RoutineHead);
    end
    else
    begin
      Builder.Append(TypeHead);
    end;
    // Zeilen davor leer, damit Positionen gleich bleiben; Zeile 0 trägt den Kopf.
    for Index := 1 to High(Lines) do
    begin
      Builder.Append(#10);
      if (Index >= AScope.FirstLine) and (Index <= AScope.LastLine) then
      begin
        Builder.Append(Lines[Index].TrimRight([#13]));
      end;
    end;
    Builder.Append(#10);
    if AScope.Kind = TCompletionScopeKind.Routine then
    begin
      Builder.Append(RoutineTail);
    end
    else
    begin
      Builder.Append(TypeTail);
    end;
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
  begin
    Exit;
  end;
  Line := Lines[APosition.Line];
  Character := APosition.Character;
  if Character > Length(Line) then
  begin
    Character := Length(Line);
  end;
  while (Character > 0) and CharInSet(Line[Character], ['A'..'Z', 'a'..'z', '0'..'9', '_', '&']) do
  begin
    Dec(Character);
  end;
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
  begin
    Exit;
  end;
  // Ohne Fehler im ganzen Baum keine eigene Prüfung.
  Broken := False;
  for Diagnostic in ATree.Diagnostics do
  begin
    if not Diagnostic.TreeIntact then
    begin
      Broken := True;
    end;
  end;
  if not Broken then
  begin
    Exit;
  end;
  Scope := ScopeAt(ATree.Tokens, APosition);
  if (Scope.Kind = TCompletionScopeKind.None) or (Scope.FirstLine < 1) then
  begin
    Exit;
  end;
  Limit := WordStart(AText, APosition);
  Tree := TSyntaxTreeCache.Parse(ScopeText(AText, Scope));
  try
    for Diagnostic in Tree.Diagnostics do
    begin
      if not Diagnostic.TreeIntact and (Diagnostic.StartPos.Line >= Scope.FirstLine) and
        Before(Diagnostic.StartPos, Limit) then
      begin
        Result.Line := Diagnostic.StartPos.Line;
        Result.Character := Diagnostic.StartPos.Character;
        Result.Message := Diagnostic.Message;
        if ACount = 0 then
        begin
          Result.Trust := TCompletionTrust.Unknown;
        end
        else
        begin
          Result.Trust := TCompletionTrust.Limited;
        end;
        Exit;
      end;
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
  begin
    Exit;
  end;
  Notice := TJSONObject.Create;
  Notice.AddPair('trust', TrustName(ANotice.Trust));
  Notice.AddPair('line', TJSONNumber.Create(ANotice.Line));
  Notice.AddPair('character', TJSONNumber.Create(ANotice.Character));
  Notice.AddPair('message', ANotice.Message);
  AList.AddPair('syntaxNotice', Notice);
end;

end.
