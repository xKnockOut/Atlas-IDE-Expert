unit Atlas.Common.Lsp.SignatureHelp;

// Parameterhilfe (textDocument/signatureHelp): zeigt beim Aufruf alle Überladungen der Routine,
// hebt den aktiven Parameter hervor und übernimmt die ///-Dokumentation samt <param>-Texten
// (TXmlDoc mit <inheritdoc/>, #654).
// Der Aufruf wird an den Tokens vor dem Cursor erkannt: die innerste offene Klammer hinter
// einem Bezeichner; Kommas auf derselben Ebene zählen den aktiven Parameter.
// Überladungen nach Argumenttypen (#498): Jedes bisherige Argument bekommt einen Typ (Literale: Zeichen, String,
// Zahl, Boolean, nil, Menge; Bezeichner über die Namensauflösung, Aufzählungswerte über ihren Typ) und wird mit dem
// Parametertyp verglichen (TNameResolver.ArgumentFits). Unbekannte Typen gelten als verträglich. Jede Signatur
// trägt das Ergebnis in data.fits und data.mismatch (erstes unverträgliches Argument, -1); vorgewählt wird die
// erste verträgliche mit genug Parametern.

interface

{$SCOPEDENUMS ON}

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.JsonRpc.Dispatcher,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Index.Contract,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Lsp.Hover;

type
  TCallSite = record
    /// <summary>Position des Routinennamens vor der Klammer.</summary>
    NamePosition: TTextPosition;
    /// <summary>Nullbasiert.</summary>
    ActiveParameter: Integer;
    Found: Boolean;
    /// <summary>Tokens der bisherigen Argumente (Index in ATree.Tokens, Last einschließlich), das gerade getippte
    /// eingeschlossen; First &gt; Last bei leerem Argument (#498).</summary>
    ArgumentFirst: TArray<Integer>;
    ArgumentLast: TArray<Integer>;
  end;

  TSignatureParameter = record
    /// <summary>Bereich im Label der Signatur (Zeichen, nullbasiert, Ende exklusiv).</summary>
    StartIndex: Integer;
    EndIndex: Integer;
    Documentation: string;
    /// <summary>Typ hinter dem Doppelpunkt ohne Vorgabewert; '' bei untypisierten Parametern (#498).</summary>
    TypeName: string;
  end;

  TSignature = record
    Text: string;
    Documentation: string;
    Parameters: TArray<TSignatureParameter>;
    /// <summary>Kopf mit Typ-Präfix (procedure TFoo.Bar), also der Rumpf einer Methode.</summary>
    Qualified: Boolean;
    /// <summary>Alle bisherigen Argumente sind mit ihren Parametern verträglich (#498).</summary>
    Fits: Boolean;
    /// <summary>Erstes unverträgliches Argument, -1 ohne.</summary>
    Mismatch: Integer;
  end;

  TSignatureHelp = record
    Signatures: TArray<TSignature>;
    ActiveSignature: Integer;
    ActiveParameter: Integer;
    function Found: Boolean;
  end;

  TLspSignatureHelp = class
  public const
    Method = 'textDocument/signatureHelp';
  private
    FStore: IDocumentStore;
    FIndex: ISymbolIndex;
    FEnsureUnit: TEnsureUnitFunc;
    FReadText: THoverReadText;
    FNamespaces: TArray<string>;
    function Handle(const AParams: TJSONValue; const ACancellation: IJsonRpcCancellationToken): TJSONValue;
  private
    /// <summary>Unter TLspNamespaces gelesen und ersetzt (Code-Review A-03): Die Komposition setzt sie
    /// beim Laden eines Projekts, Anfragen lesen sie in Worker-Threads.</summary>
    function GetNamespaces: TArray<string>;
    procedure SetNamespaces(const AValue: TArray<string>);
  public
    constructor Create(const AStore: IDocumentStore; const AIndex: ISymbolIndex; const AReadText: THoverReadText;
      const AEnsureUnit: TEnsureUnitFunc = nil);
    procedure Attach(ADispatcher: TJsonRpcDispatcher);
    /// <summary>signatureHelpProvider mit ( und , als Auslöser.</summary>
    class function Capability: TJSONObject; static;
    /// <summary>Innerster offener Aufruf vor APosition.</summary>
    class function CallSiteAt(ATree: TSyntaxTree; const APosition: TTextPosition): TCallSite; static;
    /// <summary>Typ des Arguments aus ATokens[AFirst..ALast] (#498): Char, string, Integer, Double, Boolean, nil,
    /// [] oder der Typ eines Bezeichners; '' wenn unbekannt.</summary>
    class function ArgumentType(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName: string;
      AFirst, ALast: Integer): string; static;
    /// <summary>Setzt Fits und Mismatch von ASignature für AArgumentTypes.</summary>
    class procedure Match(var ASignature: TSignature; const AArgumentTypes: TArray<string>); static;
    /// <summary>Kopf einer Routine ab ALine/AColumn bis zum ; hinter der Parameterliste, auf eine Zeile gebracht.</summary>
    class function ParseSignature(const ALines: TArray<string>; ALine, AColumn: Integer): TSignature; static;
    class function HelpAt(AResolver: TNameResolver; const AIndex: ISymbolIndex; ATree: TSyntaxTree;
      const ATreeText, AFileName: string; const APosition: TTextPosition;
      const AReadText: THoverReadText): TSignatureHelp; static;
    /// <summary>SignatureHelp des LSP; JSON-null ohne Signaturen. Der Aufrufer übernimmt das Objekt.</summary>
    class function ToJson(const AHelp: TSignatureHelp): TJSONValue; static;
    property Namespaces: TArray<string> read GetNamespaces write SetNamespaces;
  end;

implementation

uses
  Atlas.Common.Lsp.Internals.Namespaces,
  Atlas.Common.Index.Files,
  System.Math,
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Lsp.Positions,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Pascal.XmlDoc,
  Atlas.Common.Lsp.Documentation,
  Atlas.Common.Lsp.Internals.Cancellation,
  Atlas.Common.Editing.InterfaceStubs,
  Atlas.Text.Lines;

const
  RoutineKinds = [TIndexSymbolKind.Method, TIndexSymbolKind.Constructor_, TIndexSymbolKind.Routine];
  MaxHeaderLines = 50;
  ParameterModifiers: array[0..4] of string = ('const ', 'var ', 'out ', 'constref ', '[ref] ');

function ComparePositions(const A, B: TTextPosition): Integer;
begin
  if A.Line <> B.Line then
    Result := A.Line - B.Line
  else
    Result := A.Character - B.Character;
end;

function CollapseSpaces(const AText: string): string;
var
  Index: Integer;
  Space: Boolean;
begin
  Result := '';
  Space := False;
  for Index := 1 to Length(AText) do
    if CharInSet(AText[Index], [' ', #9, #10, #13]) then
      Space := Result <> ''
    else
    begin
      if Space then
        Result := Result + ' ';
      Space := False;
      Result := Result + AText[Index];
    end;
end;

{ TSignatureHelp }

function TSignatureHelp.Found: Boolean;
begin
  Result := Length(Signatures) > 0;
end;

{ TLspSignatureHelp }

function TLspSignatureHelp.GetNamespaces: TArray<string>;
begin
  Result := TLspNamespaces.Read(FNamespaces);
end;

procedure TLspSignatureHelp.SetNamespaces(const AValue: TArray<string>);
begin
  TLspNamespaces.Write(FNamespaces, AValue);
end;

constructor TLspSignatureHelp.Create(const AStore: IDocumentStore; const AIndex: ISymbolIndex;
  const AReadText: THoverReadText; const AEnsureUnit: TEnsureUnitFunc);
begin
  inherited Create;
  FStore := AStore;
  FIndex := AIndex;
  FReadText := AReadText;
  FEnsureUnit := AEnsureUnit;
end;

procedure TLspSignatureHelp.Attach(ADispatcher: TJsonRpcDispatcher);
begin
  ADispatcher.RegisterConcurrentRequest(Method, Handle);
end;

class function TLspSignatureHelp.Capability: TJSONObject;
var
  Triggers, Retriggers: TJSONArray;
begin
  Triggers := TJSONArray.Create;
  Triggers.Add('(');
  Triggers.Add(',');
  Retriggers := TJSONArray.Create;
  Retriggers.Add(')');
  Result := TJSONObject.Create;
  Result.AddPair('triggerCharacters', Triggers);
  Result.AddPair('retriggerCharacters', Retriggers);
end;

class function TLspSignatureHelp.CallSiteAt(ATree: TSyntaxTree; const APosition: TTextPosition): TCallSite;
var
  Tokens: TArray<TPascalToken>;
  Index, Last, Depth, Commas, Previous, SpanEnd: Integer;
  Token: TPascalToken;
  Firsts, Lasts: TArray<Integer>;
begin
  Result := Default(TCallSite);
  if ATree = nil then
    Exit;
  Tokens := ATree.Tokens;
  Last := -1;
  for Index := 0 to High(Tokens) do
  begin
    if ComparePositions(Tokens[Index].StartPos, APosition) >= 0 then
      Break;
    Last := Index;
  end;
  Depth := 0;
  Commas := 0;
  // Argumente rückwärts gesammelt (#498): SpanEnd ist das letzte Token des Arguments links vom nächsten Komma.
  SpanEnd := Last;
  Firsts := nil;
  Lasts := nil;
  for Index := Last downto 0 do
  begin
    Token := Tokens[Index];
    if Token.Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive] then
      Continue;
    if Token.IsSymbol(')') or Token.IsSymbol(']') then
      Inc(Depth)
    else if Token.IsSymbol('(') or Token.IsSymbol('[') then
    begin
      if Depth > 0 then
      begin
        Dec(Depth);
        Continue;
      end;
      Previous := Index - 1;
      while (Previous >= 0) and (Tokens[Previous].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]) do
        Dec(Previous);
      if Token.IsSymbol('(') and (Previous >= 0) and (Tokens[Previous].Kind = TPascalTokenKind.Identifier) then
      begin
        Result.NamePosition := Tokens[Previous].StartPos;
        Result.ActiveParameter := Commas;
        Result.Found := True;
        Firsts := [Index + 1] + Firsts;
        Lasts := [SpanEnd] + Lasts;
        Result.ArgumentFirst := Firsts;
        Result.ArgumentLast := Lasts;
        Exit;
      end;
      // Klammer um einen Ausdruck oder eine Menge: sie ist selbst ein Argument des äußeren Aufrufs.
      Commas := 0;
      Firsts := nil;
      Lasts := nil;
      SpanEnd := Last;
    end
    else if Depth = 0 then
    begin
      if Token.IsSymbol(',') then
      begin
        Inc(Commas);
        Firsts := [Index + 1] + Firsts;
        Lasts := [SpanEnd] + Lasts;
        SpanEnd := Index - 1;
      end
      else if Token.IsSymbol(';') or Token.IsKeyword('begin') or Token.IsKeyword('end') or
        Token.IsKeyword('then') or Token.IsKeyword('do') or Token.IsKeyword('var') then
        Exit;
    end;
  end;
end;

class function TLspSignatureHelp.ParseSignature(const ALines: TArray<string>; ALine, AColumn: Integer): TSignature;
var
  Raw, Text: string;
  Line, Index, Depth, Open, Close, Start, Keyword, Dot: Integer;
  Done: Boolean;
  Groups: TList<TSignatureParameter>;
  Parameter: TSignatureParameter;

  procedure AddGroup(AFrom, ATo: Integer);
  var
    GroupText, NamesText, Item, Modifier, TypeText: string;
    Offset, Skip, ColonAt, Search, EqualAt: Integer;
  begin
    // AFrom/ATo sind 1-basierte Positionen in Text; ATo exklusiv.
    GroupText := Copy(Text, AFrom, ATo - AFrom);
    Skip := Length(GroupText) - Length(TrimLeft(GroupText));
    Inc(AFrom, Skip);
    GroupText := Trim(GroupText);
    if GroupText = '' then
      Exit;
    ColonAt := Pos(':', GroupText);
    TypeText := '';
    if ColonAt = 0 then
      NamesText := GroupText
    else
    begin
      NamesText := Copy(GroupText, 1, ColonAt - 1);
      // Typ ohne Vorgabewert, ohne Unit davor (System.Boolean → Boolean, #498).
      TypeText := Copy(GroupText, ColonAt + 1, MaxInt);
      EqualAt := Pos('=', TypeText);
      if EqualAt > 0 then
        TypeText := Copy(TypeText, 1, EqualAt - 1);
      TypeText := Trim(TypeText);
      if (Pos('<', TypeText) = 0) and (Pos(' ', TypeText) = 0) and (LastDelimiter('.', TypeText) > 0) then
        TypeText := Copy(TypeText, LastDelimiter('.', TypeText) + 1, MaxInt);
    end;
    Parameter.TypeName := TypeText;
    // const/var/out/constref vor den Namen überspringen.
    for Modifier in ParameterModifiers do
      if StartsText(Modifier, NamesText) then
        Delete(NamesText, 1, Length(Modifier));
    if Pos(',', NamesText) = 0 then
    begin
      Parameter.StartIndex := AFrom - 1;
      Parameter.EndIndex := AFrom - 1 + Length(GroupText);
      Parameter.Documentation := '';
      Groups.Add(Parameter);
      Exit;
    end;
    // A, B: Integer → je Name ein Parameter, hervorgehoben wird nur der Name.
    Search := AFrom;
    for Item in NamesText.Split([',']) do
    begin
      Offset := PosEx(Trim(Item), Text, Search);
      Parameter.StartIndex := Offset - 1;
      Parameter.EndIndex := Offset - 1 + Length(Trim(Item));
      Parameter.Documentation := '';
      Groups.Add(Parameter);
      Search := Offset + Length(Trim(Item));
    end;
  end;

begin
  Result := Default(TSignature);
  Result.Fits := True;
  Result.Mismatch := -1;
  // Kopf einsammeln: bis zum ; außerhalb von Klammern.
  Raw := '';
  Depth := 0;
  Done := False;
  Line := ALine;
  while not Done and (Line <= High(ALines)) and (Line < ALine + MaxHeaderLines) do
  begin
    if Line = ALine then
      Text := Copy(ALines[Line], AColumn + 1, MaxInt)
    else
      Text := ALines[Line];
    for Index := 1 to Length(Text) do
    begin
      case Text[Index] of
        '(': Inc(Depth);
        ')': Dec(Depth);
        ';':
          if Depth = 0 then
          begin
            Raw := Raw + Copy(Text, 1, Index - 1);
            Done := True;
            Break;
          end;
      end;
    end;
    if not Done then
      Raw := Raw + Text + ' ';
    Inc(Line);
  end;
  Text := CollapseSpaces(Raw);
  // procedure TFoo.Bar → procedure Bar
  Keyword := Pos(' ', Text);
  Open := Pos('(', Text);
  if Keyword > 0 then
  begin
    if Open > 0 then
      Dot := LastDelimiter('.', Copy(Text, 1, Open - 1))
    else
      Dot := LastDelimiter('.', Text);
    if Dot > Keyword then
    begin
      Delete(Text, Keyword + 1, Dot - Keyword);
      Result.Qualified := True;
    end;
  end;
  Result.Text := Text;
  Open := Pos('(', Text);
  if Open = 0 then
    Exit;
  Depth := 0;
  Close := 0;
  for Index := Open to Length(Text) do
    if Text[Index] = '(' then
      Inc(Depth)
    else if Text[Index] = ')' then
    begin
      Dec(Depth);
      if Depth = 0 then
      begin
        Close := Index;
        Break;
      end;
    end;
  if Close = 0 then
    Exit;
  Groups := TList<TSignatureParameter>.Create;
  try
    Start := Open + 1;
    Depth := 0;
    for Index := Open + 1 to Close do
      if (Index = Close) or (Text[Index] = ';') and (Depth = 0) then
      begin
        AddGroup(Start, Index);
        Start := Index + 1;
      end
      else if Text[Index] = '(' then
        Inc(Depth)
      else if Text[Index] = ')' then
        Dec(Depth);
    Result.Parameters := Groups.ToArray;
  finally
    Groups.Free;
  end;
end;

/// <summary>Name ohne Unit bzw. umgebenden Typ davor (System.Boolean → Boolean); Generics bleiben.</summary>
function LastPart(const AName: string): string;
begin
  if Pos('<', AName) > 0 then
    Result := AName
  else
    Result := Copy(AName, LastDelimiter('.', AName) + 1, MaxInt);
end;

/// <summary>Zeichen in einem String-Literal ('it''s' = 4); -1 bei mehrzeiligen.</summary>
function LiteralLength(const AText: string): Integer;
begin
  if StartsStr('''''''', AText) then
    Exit(-1);
  Result := Length(StringReplace(Copy(AText, 2, Length(AText) - 2), '''''', '''', [rfReplaceAll]));
end;

class function TLspSignatureHelp.ArgumentType(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName: string;
  AFirst, ALast: Integer): string;
var
  Tokens, Parts: TArray<TPascalToken>;
  Token: TPascalToken;
  Index, Chars, Start, Count: Integer;
  Literal: Boolean;
  Resolved: TResolvedSymbol;
begin
  Result := '';
  if (ATree = nil) or (AFirst > ALast) then
    Exit;
  Tokens := ATree.Tokens;
  Parts := nil;
  for Index := Max(AFirst, 0) to Min(ALast, High(Tokens)) do
    if not (Tokens[Index].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]) then
      Parts := Parts + [Tokens[Index]];
  if Length(Parts) = 0 then
    Exit;
  if Parts[0].IsSymbol('[') then
    Exit('[]');
  // Zeichen und Strings, auch zusammengesetzt wie 'a'#13'b'; ein offenes Literal wird noch getippt.
  Chars := 0;
  Literal := True;
  for Token in Parts do
    if not Token.Terminated then
      Exit
    else if Token.Kind = TPascalTokenKind.StringLiteral then
    begin
      Count := LiteralLength(Token.Text);
      if Count < 0 then
        Exit('string');
      Inc(Chars, Count);
    end
    else if Token.Kind = TPascalTokenKind.CharLiteral then
      Inc(Chars)
    else
      Literal := False;
  if Literal then
  begin
    if Chars = 1 then
      Result := 'Char'
    else
      Result := 'string';
    Exit;
  end;
  // Zahlen, auch mit Vorzeichen.
  Start := 0;
  if (Length(Parts) = 2) and (Parts[0].IsSymbol('-') or Parts[0].IsSymbol('+')) then
    Start := 1;
  if (Length(Parts) = Start + 1) and (Parts[Start].Kind = TPascalTokenKind.Number) then
  begin
    if not CharInSet(Parts[Start].Text[1], ['$', '%']) and ((Pos('.', Parts[Start].Text) > 0) or
      ContainsText(Parts[Start].Text, 'e')) then
      Result := 'Double'
    else
      Result := 'Integer';
    Exit;
  end;
  if Length(Parts) = 1 then
  begin
    if Parts[0].IsKeyword('nil') then
      Exit('nil');
    if (Parts[0].Kind = TPascalTokenKind.Identifier) and (SameText(Parts[0].Text, 'True') or
      SameText(Parts[0].Text, 'False')) then
      Exit('Boolean');
  end;
  // Bezeichner oder Kette A.B.C; alles andere (Aufrufe, Ausdrücke) bleibt unbekannt.
  if not Odd(Length(Parts)) then
    Exit;
  for Index := 0 to High(Parts) do
    if Odd(Index) and not Parts[Index].IsSymbol('.') then
      Exit
    else if not Odd(Index) and (Parts[Index].Kind <> TPascalTokenKind.Identifier) then
      Exit;
  if AResolver = nil then
    Exit;
  Resolved := AResolver.Resolve(ATree, AFileName, Parts[High(Parts)].StartPos);
  if not (Resolved.Kind in [TResolvedKind.Symbol, TResolvedKind.Local]) then
    Exit;
  // Aufzählungswerte tragen ihren Typ als Container; Routinen bleiben unbekannt (Methodenzeiger).
  if Resolved.SymbolKind = TIndexSymbolKind.EnumMember then
    Result := LastPart(Resolved.Container)
  else if Resolved.SymbolKind in [TIndexSymbolKind.Variable, TIndexSymbolKind.Field, TIndexSymbolKind.Property_,
    TIndexSymbolKind.Constant] then
    Result := LastPart(Trim(Resolved.TypeName));
end;

class procedure TLspSignatureHelp.Match(var ASignature: TSignature; const AArgumentTypes: TArray<string>);
var
  Index: Integer;
begin
  ASignature.Fits := True;
  ASignature.Mismatch := -1;
  // Zu viele Argumente zählt der Hint selbst; hier nur die Typen.
  for Index := 0 to Min(High(AArgumentTypes), High(ASignature.Parameters)) do
    if not TNameResolver.ArgumentFits(ASignature.Parameters[Index].TypeName, AArgumentTypes[Index]) then
    begin
      ASignature.Fits := False;
      ASignature.Mismatch := Index;
      Exit;
    end;
end;

procedure ApplyDocumentation(var ASignature: TSignature; const ADoc: TXmlDoc);
var
  Section: TXmlDocSection;
  Name, Text: string;
  Index: Integer;
begin
  // Alles außer den Parametern an die Signatur, <param> an den passenden Parameter. Klartext: Der Hint
  // des Plugins und der Client von RAD Studio zeigen kein Markdown; Namen aus cref bleiben erhalten.
  ASignature.Documentation := ADoc.ToPlainText(False);
  for Section in ADoc.Sections do
  begin
    if Section.Kind <> TXmlDocSectionKind.Param then
      Continue;
    Name := Section.Name;
    for Index := 0 to High(ASignature.Parameters) do
    begin
      Text := Copy(ASignature.Text, ASignature.Parameters[Index].StartIndex + 1,
        ASignature.Parameters[Index].EndIndex - ASignature.Parameters[Index].StartIndex);
      if SameText(Text, Name) or StartsText(Name + ':', Text) or StartsText(Name + ' ', Text) or
        ContainsText(Text, ' ' + Name + ':') or ContainsText(Text, ' ' + Name + ' ') or
        StartsText(Name + ',', Text) or ContainsText(Text, ' ' + Name + ',') then
      begin
        ASignature.Parameters[Index].Documentation := Section.Text;
        Break;
      end;
    end;
  end;
end;

class function TLspSignatureHelp.HelpAt(AResolver: TNameResolver; const AIndex: ISymbolIndex; ATree: TSyntaxTree;
  const ATreeText, AFileName: string; const APosition: TTextPosition;
  const AReadText: THoverReadText): TSignatureHelp;
var
  Site: TCallSite;
  Resolved: TResolvedSymbol;
  OwnerUnit: TUnitIndex;
  Text: string;
  Lines: TArray<string>;
  Starts: TList<TTextPosition>;
  StartSymbols: TList<TResolvedSymbol>;
  Signatures: TList<TSignature>;
  Seen: TList<string>;
  Symbol: TIndexSymbol;
  HasInterface: Boolean;
  Start: TTextPosition;
  Signature: TSignature;
  Key: string;
  Index: Integer;
  Reader: TDocReadText;
  ArgumentTypes: TArray<string>;
  SignatureLines, Bindings: TArray<string>;
  Line: Integer;
  Binding: string;
begin
  Result := Default(TSignatureHelp);
  Site := CallSiteAt(ATree, APosition);
  if not Site.Found then
    Exit;
  Resolved := AResolver.Resolve(ATree, AFileName, Site.NamePosition);
  if not (Resolved.Kind in [TResolvedKind.Symbol, TResolvedKind.Local]) or not (Resolved.SymbolKind in RoutineKinds) then
    Exit;
  if SameText(Resolved.FileName, AFileName) then
    Text := ATreeText
  else if not (Assigned(AReadText) and AReadText(Resolved.FileName, Text)) then
    Exit;
  Lines := TTextLines.SplitLines(Text);
  Reader := TLspDocumentation.Reader(AFileName, ATreeText, AReadText);
  Starts := TList<TTextPosition>.Create;
  // Typargumente ohne Unit davor ("T=TKunde" statt "T=Listen.TKunde").
  Bindings := nil;
  for Binding in Resolved.Bindings do
    Bindings := Bindings + [Copy(Binding, 1, Pos('=', Binding)) +
      AResolver.UnqualifyType(Copy(Binding, Pos('=', Binding) + 1, MaxInt))];
  StartSymbols := TList<TResolvedSymbol>.Create;
  Signatures := TList<TSignature>.Create;
  Seen := TList<string>.Create;
  try
    // Überladungen: gleicher Name im selben Typ bzw. auf Unit-Ebene derselben Unit.
    if Resolved.Kind = TResolvedKind.Local then
    begin
      Starts.Add(Resolved.Range.StartPos);
      StartSymbols.Add(Resolved);
    end
    else
    begin
      if SameText(Resolved.FileName, AFileName) then
        OwnerUnit := TIndexExtractor.Extract(ATree, AFileName)
      else if not TIndexFiles.UnitOf(AIndex, Resolved.FileName, OwnerUnit) then
        Exit;
      HasInterface := False;
      for Symbol in OwnerUnit.Symbols do
        if (Symbol.Kind in RoutineKinds) and SameText(Symbol.Name, Resolved.Name) and
          SameText(Symbol.Container, Resolved.Container) and Symbol.InInterface then
          HasInterface := True;
      // Rümpfe globaler Routinen aus interface weglassen: sie dürfen die Parameter auslassen.
      for Symbol in OwnerUnit.Symbols do
        if (Symbol.Kind in RoutineKinds) and SameText(Symbol.Name, Resolved.Name) and
          SameText(Symbol.Container, Resolved.Container) and (Symbol.InInterface or not HasInterface) and
          SameText(OwnerUnit.SymbolFile(Symbol), Resolved.FileName) then
        begin
          Starts.Add(Symbol.Range.StartPos);
          StartSymbols.Add(AResolver.SymbolFrom(OwnerUnit, Symbol));
        end;
    end;
    for Index := 0 to Starts.Count - 1 do
    begin
      Start := Starts[Index];
      if (Start.Line < 0) or (Start.Line > High(Lines)) then
        Continue;
      // Gebundene Typparameter (#450): FItems: TObjectList<TKunde> zeigt Add(const Value: TKunde). Nur die
      // Zeilen des Kopfs; die Spalte des Anfangs bleibt, weil davor kein Typparameter steht.
      SignatureLines := Lines;
      if Length(Bindings) > 0 then
      begin
        SignatureLines := Copy(Lines);
        for Line := Start.Line to Min(High(SignatureLines), Start.Line + MaxHeaderLines) do
          SignatureLines[Line] := TInterfaceStubs.SubstituteWords(SignatureLines[Line], Bindings);
      end;
      Signature := ParseSignature(SignatureLines, Start.Line, Start.Character);
      // Deklaration und Rumpf derselben Routine nur einmal; die Deklaration steht vorn und trägt die Doku.
      Key := UpperCase(StringReplace(Signature.Text, ' ', '', [rfReplaceAll]));
      if (Signature.Text = '') or Signature.Qualified or Seen.Contains(Key) then
        Continue;
      Seen.Add(Key);
      ApplyDocumentation(Signature, TLspDocumentation.Load(AResolver, StartSymbols[Index], Lines, Start.Line,
        Reader));
      Signatures.Add(Signature);
    end;
    Result.Signatures := Signatures.ToArray;
  finally
    Seen.Free;
    Signatures.Free;
    StartSymbols.Free;
    Starts.Free;
  end;
  Result.ActiveParameter := Site.ActiveParameter;
  // Argumenttypen (#498), erst nach dem Einsammeln der Überladungen aufgelöst.
  ArgumentTypes := nil;
  for Index := 0 to High(Site.ArgumentFirst) do
    ArgumentTypes := ArgumentTypes + [ArgumentType(AResolver, ATree, AFileName, Site.ArgumentFirst[Index],
      Site.ArgumentLast[Index])];
  for Index := 0 to High(Result.Signatures) do
    Match(Result.Signatures[Index], ArgumentTypes);
  // Erste verträgliche Überladung mit genug Parametern, sonst die erste mit genug Parametern.
  Result.ActiveSignature := -1;
  for Index := 0 to High(Result.Signatures) do
    if (Length(Result.Signatures[Index].Parameters) > Site.ActiveParameter) and Result.Signatures[Index].Fits then
    begin
      Result.ActiveSignature := Index;
      Break;
    end;
  if Result.ActiveSignature < 0 then
    for Index := 0 to High(Result.Signatures) do
      if Length(Result.Signatures[Index].Parameters) > Site.ActiveParameter then
      begin
        Result.ActiveSignature := Index;
        Break;
      end;
  if Result.ActiveSignature < 0 then
    Result.ActiveSignature := 0;
end;

class function TLspSignatureHelp.ToJson(const AHelp: TSignatureHelp): TJSONValue;
var
  Signatures, Parameters, LabelRange: TJSONArray;
  Signature, Parameter, Documentation, Data: TJSONObject;
  Item: TSignature;
  Index: Integer;
begin
  if not AHelp.Found then
    Exit(TJSONNull.Create);
  Signatures := TJSONArray.Create;
  for Item in AHelp.Signatures do
  begin
    Signature := TJSONObject.Create;
    Signatures.AddElement(Signature);
    Signature.AddPair('label', Item.Text);
    if Item.Documentation <> '' then
    begin
      Documentation := TJSONObject.Create;
      Documentation.AddPair('kind', 'markdown');
      Documentation.AddPair('value', Item.Documentation);
      Signature.AddPair('documentation', Documentation);
    end;
    Parameters := TJSONArray.Create;
    Signature.AddPair('parameters', Parameters);
    for Index := 0 to High(Item.Parameters) do
    begin
      Parameter := TJSONObject.Create;
      Parameters.AddElement(Parameter);
      LabelRange := TJSONArray.Create;
      LabelRange.Add(Item.Parameters[Index].StartIndex);
      LabelRange.Add(Item.Parameters[Index].EndIndex);
      Parameter.AddPair('label', LabelRange);
      if Item.Parameters[Index].Documentation <> '' then
        Parameter.AddPair('documentation', Item.Parameters[Index].Documentation);
    end;
    // Verträglichkeit der bisherigen Argumente (#498), für den Parameter-Hint des Plugins.
    Data := TJSONObject.Create;
    Data.AddPair('fits', TJSONBool.Create(Item.Fits));
    Data.AddPair('mismatch', TJSONNumber.Create(Item.Mismatch));
    Signature.AddPair('data', Data);
  end;
  Result := TJSONObject.Create;
  TJSONObject(Result).AddPair('signatures', Signatures);
  TJSONObject(Result).AddPair('activeSignature', TJSONNumber.Create(AHelp.ActiveSignature));
  TJSONObject(Result).AddPair('activeParameter', TJSONNumber.Create(AHelp.ActiveParameter));
end;

function TLspSignatureHelp.Handle(const AParams: TJSONValue; const ACancellation: IJsonRpcCancellationToken): TJSONValue;
var
  Cancellation: IPascalCancellation;
  Uri: string;
  PositionValue: TJSONValue;
  Document: ITextDocument;
  Tree: TSyntaxTree;
  Shared: ISharedSyntaxTree;
  Resolver: TNameResolver;
  Help: TSignatureHelp;
begin
  if not ((AParams is TJSONObject) and TJSONObject(AParams).TryGetValue<string>('textDocument.uri', Uri) and
    TJSONObject(AParams).TryGetValue<TJSONValue>('position', PositionValue)) then
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams,
      'Felder "textDocument.uri" und "position" fehlen');
  if not FStore.TryGet(Uri, Document) then
    Exit(TJSONNull.Create);
  Cancellation := TRequestCancellation.Create(ACancellation);
  Shared := TSyntaxTreeCache.Get(Document, Cancellation);
  Tree := Shared.Tree;
  ACancellation.ThrowIfCancellationRequested;
  Resolver := TNameResolver.Create(FIndex, FEnsureUnit);
  try
    Resolver.Namespaces := Namespaces;
    Help := HelpAt(Resolver, FIndex, Tree, Document.Text, TDocumentUris.ToPath(Uri),
      TLspPositions.ReadPosition(PositionValue), FReadText);
  finally
    Resolver.Free;
  end;
  Result := ToJson(Help);
end;

end.
