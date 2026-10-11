unit Atlas.Common.Lsp.SignatureHelp;

// Parameterhilfe (textDocument/signatureHelp): zeigt beim Aufruf alle Überladungen der Routine,
// hebt den aktiven Parameter hervor und übernimmt die ///-Dokumentation samt <param>-Texten.
// Der Aufruf wird an den Tokens vor dem Cursor erkannt: die innerste offene Klammer hinter
// einem Bezeichner; Kommas auf derselben Ebene zählen den aktiven Parameter.

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
  end;

  TSignatureParameter = record
    /// <summary>Bereich im Label der Signatur (Zeichen, nullbasiert, Ende exklusiv).</summary>
    StartIndex: Integer;
    EndIndex: Integer;
    Documentation: string;
  end;

  TSignature = record
    Text: string;
    Documentation: string;
    Parameters: TArray<TSignatureParameter>;
    /// <summary>Kopf mit Typ-Präfix (procedure TFoo.Bar), also der Rumpf einer Methode.</summary>
    Qualified: Boolean;
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
  public
    constructor Create(const AStore: IDocumentStore; const AIndex: ISymbolIndex; const AReadText: THoverReadText;
      const AEnsureUnit: TEnsureUnitFunc = nil);
    procedure Attach(ADispatcher: TJsonRpcDispatcher);
    /// <summary>signatureHelpProvider mit ( und , als Auslöser.</summary>
    class function Capability: TJSONObject; static;
    /// <summary>Innerster offener Aufruf vor APosition.</summary>
    class function CallSiteAt(ATree: TSyntaxTree; const APosition: TTextPosition): TCallSite; static;
    /// <summary>Kopf einer Routine ab ALine/AColumn bis zum ; hinter der Parameterliste, auf eine Zeile gebracht.</summary>
    class function ParseSignature(const ALines: TArray<string>; ALine, AColumn: Integer): TSignature; static;
    class function HelpAt(AResolver: TNameResolver; const AIndex: ISymbolIndex; ATree: TSyntaxTree;
      const ATreeText, AFileName: string; const APosition: TTextPosition;
      const AReadText: THoverReadText): TSignatureHelp; static;
    /// <summary>SignatureHelp des LSP; JSON-null ohne Signaturen. Der Aufrufer übernimmt das Objekt.</summary>
    class function ToJson(const AHelp: TSignatureHelp): TJSONValue; static;
    property Namespaces: TArray<string> read FNamespaces write FNamespaces;
  end;

implementation

uses
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Lsp.Positions,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Lsp.Internals.Cancellation;

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

function SplitLines(const AText: string): TArray<string>;
var
  Index, Start: Integer;
  Line: string;
begin
  Result := nil;
  Start := 1;
  for Index := 1 to Length(AText) + 1 do
    if (Index > Length(AText)) or (AText[Index] = #10) then
    begin
      Line := Copy(AText, Start, Index - Start);
      if (Line <> '') and (Line[Length(Line)] = #13) then
        SetLength(Line, Length(Line) - 1);
      Result := Result + [Line];
      Start := Index + 1;
    end;
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
  Index, Last, Depth, Commas, Previous: Integer;
  Token: TPascalToken;
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
        Exit;
      end;
      // Klammer um einen Ausdruck oder eine Menge: sie ist selbst ein Argument des äußeren Aufrufs.
      Commas := 0;
    end
    else if Depth = 0 then
    begin
      if Token.IsSymbol(',') then
        Inc(Commas)
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
    GroupText, NamesText, Item, Modifier: string;
    Offset, Skip, ColonAt, Search: Integer;
  begin
    // AFrom/ATo sind 1-basierte Positionen in Text; ATo exklusiv.
    GroupText := Copy(Text, AFrom, ATo - AFrom);
    Skip := Length(GroupText) - Length(TrimLeft(GroupText));
    Inc(AFrom, Skip);
    GroupText := Trim(GroupText);
    if GroupText = '' then
      Exit;
    ColonAt := Pos(':', GroupText);
    if ColonAt = 0 then
      NamesText := GroupText
    else
      NamesText := Copy(GroupText, 1, ColonAt - 1);
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

procedure ApplyDocumentation(var ASignature: TSignature; const ADocumentation: string);
var
  Part, Name, Rest, Text: string;
  Index: Integer;
begin
  // DocumentationAbove liefert <param name="X"> als eigene Absätze "*X*: …".
  ASignature.Documentation := '';
  for Part in ADocumentation.Split([#10#10]) do
  begin
    if StartsStr('*', Part) and (PosEx('*: ', Part, 2) > 0) then
    begin
      Name := Copy(Part, 2, PosEx('*: ', Part, 2) - 2);
      Rest := Copy(Part, PosEx('*: ', Part, 2) + 3, MaxInt);
      for Index := 0 to High(ASignature.Parameters) do
      begin
        Text := Copy(ASignature.Text, ASignature.Parameters[Index].StartIndex + 1,
          ASignature.Parameters[Index].EndIndex - ASignature.Parameters[Index].StartIndex);
        if SameText(Text, Name) or StartsText(Name + ':', Text) or StartsText(Name + ' ', Text) or
          ContainsText(Text, ' ' + Name + ':') or ContainsText(Text, ' ' + Name + ' ') then
        begin
          ASignature.Parameters[Index].Documentation := Rest;
          Break;
        end;
      end;
    end
    else
    begin
      if ASignature.Documentation <> '' then
        ASignature.Documentation := ASignature.Documentation + #10#10;
      ASignature.Documentation := ASignature.Documentation + Part;
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
  Signatures: TList<TSignature>;
  Seen: TList<string>;
  Symbol: TIndexSymbol;
  HasInterface: Boolean;
  Start: TTextPosition;
  Signature: TSignature;
  Key: string;
  Index: Integer;
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
  Lines := SplitLines(Text);
  Starts := TList<TTextPosition>.Create;
  Signatures := TList<TSignature>.Create;
  Seen := TList<string>.Create;
  try
    // Überladungen: gleicher Name im selben Typ bzw. auf Unit-Ebene derselben Unit.
    if Resolved.Kind = TResolvedKind.Local then
      Starts.Add(Resolved.Range.StartPos)
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
          Starts.Add(Symbol.Range.StartPos);
    end;
    for Start in Starts do
    begin
      if (Start.Line < 0) or (Start.Line > High(Lines)) then
        Continue;
      Signature := ParseSignature(Lines, Start.Line, Start.Character);
      // Deklaration und Rumpf derselben Routine nur einmal; die Deklaration steht vorn und trägt die Doku.
      Key := UpperCase(StringReplace(Signature.Text, ' ', '', [rfReplaceAll]));
      if (Signature.Text = '') or Signature.Qualified or Seen.Contains(Key) then
        Continue;
      Seen.Add(Key);
      ApplyDocumentation(Signature, TLspHover.DocumentationAbove(Lines, Start.Line));
      Signatures.Add(Signature);
    end;
    Result.Signatures := Signatures.ToArray;
  finally
    Seen.Free;
    Signatures.Free;
    Starts.Free;
  end;
  Result.ActiveParameter := Site.ActiveParameter;
  // Erste Überladung mit genug Parametern.
  Result.ActiveSignature := 0;
  for Index := 0 to High(Result.Signatures) do
    if Length(Result.Signatures[Index].Parameters) > Site.ActiveParameter then
    begin
      Result.ActiveSignature := Index;
      Break;
    end;
end;

class function TLspSignatureHelp.ToJson(const AHelp: TSignatureHelp): TJSONValue;
var
  Signatures, Parameters, LabelRange: TJSONArray;
  Signature, Parameter, Documentation: TJSONObject;
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
    Resolver.Namespaces := FNamespaces;
    Help := HelpAt(Resolver, FIndex, Tree, Document.Text, TDocumentUris.ToPath(Uri),
      TLspPositions.ReadPosition(PositionValue), FReadText);
  finally
    Resolver.Free;
  end;
  Result := ToJson(Help);
end;

end.
