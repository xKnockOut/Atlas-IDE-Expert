unit BDLsp.Common.Rules.Builtin.General;

// Allgemeine Regeln, Stufe 1 aus #56 (syntaktisch, ohne Typen):
//   empty-except              except-Block ohne Anweisung und ohne erklärenden Kommentar
//   interface-guid            Interface ohne GUID; mit Supports/as/QueryInterface hohe Konfidenz
//   duplicate-interface-guid  zwei Interfaces der Datei mit derselben GUID
//   file-header               Dateikopf weicht von der Vorlage ab (Option "template", Standard aus)
//   hardcoded-string          Text im Code statt resourcestring (Standard aus, niedrige Konfidenz)

interface

uses
  BDLsp.Common.Rules.Contract,
  BDLsp.Common.Rules.Registry;

type
  TEmptyExceptRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TInterfaceGuidRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TDuplicateInterfaceGuidRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TFileHeaderRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>Vorlage aus den Regeloptionen ({"template": "..."}); '' ohne.</summary>
    class function Template(const AOptions: string): string; static;
  end;

  THardcodedStringRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

/// <summary>Registriert die allgemeinen Regeln.</summary>
procedure RegisterGeneralRules(const ARegistry: TRuleRegistry);

/// <summary>Neue GUID als Interface-Zeile ohne Einrückung: ['{…}'].</summary>
function GuidLine: string;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Math,
  System.Character,
  System.JSON,
  BDLsp.Common.Documents.Contract,
  BDLsp.Common.Configuration.Contract,
  BDLsp.Common.Pascal.Contract;

function TokenRange(const AToken: TPascalToken): TTextRange;
begin
  Result := TTextRange.Create(AToken.StartPos, AToken.EndPos);
end;

function IsTrivia(const AToken: TPascalToken): Boolean;
begin
  Result := AToken.Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive];
end;

/// <summary>Nächstes Token ab AIndex, das kein Kommentar und keine Direktive ist; Length(ATokens) ohne.</summary>
function NextCode(const ATokens: TArray<TPascalToken>; AIndex: Integer): Integer;
begin
  Result := AIndex;
  while (Result <= High(ATokens)) and IsTrivia(ATokens[Result]) do
    Inc(Result);
end;

/// <summary>Vorheriges Token vor AIndex, das kein Kommentar und keine Direktive ist; -1 ohne.</summary>
function PreviousCode(const ATokens: TArray<TPascalToken>; AIndex: Integer): Integer;
begin
  Result := AIndex - 1;
  while (Result >= 0) and IsTrivia(ATokens[Result]) do
    Dec(Result);
end;

/// <summary>Einrückung der Zeile ALine von AText.</summary>
function LineIndent(const AText: string; ALine: Integer): string;
var
  Lines: TArray<string>;
  Index: Integer;
begin
  Lines := StringReplace(AText, #13#10, #10, [rfReplaceAll]).Split([#10]);
  Result := '';
  if ALine > High(Lines) then
    Exit;
  Index := 1;
  while (Index <= Length(Lines[ALine])) and CharInSet(Lines[ALine][Index], [' ', #9]) do
    Inc(Index);
  Result := Copy(Lines[ALine], 1, Index - 1);
end;

function LineBreakOf(const AText: string): string;
begin
  if Pos(#13#10, AText) > 0 then
    Result := #13#10
  else
    Result := #10;
end;

function GuidLine: string;
var
  Guid: TGUID;
begin
  if CreateGUID(Guid) <> 0 then
    raise Exception.Create('GUID konnte nicht erzeugt werden');
  Result := '[''' + GUIDToString(Guid) + ''']';
end;

{ TEmptyExceptRule }

function TEmptyExceptRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('empty-except', TRuleSeverity.Warning, 'Leerer except-Block');
end;

procedure TEmptyExceptRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Tokens: TArray<TPascalToken>;
  Index, Next: Integer;
  Commented: Boolean;
  Indent: string;
begin
  if AContext.Tree = nil then
    Exit;
  Tokens := AContext.Tree.Tokens;
  for Index := 0 to High(Tokens) do
  begin
    if (Tokens[Index].Kind <> TPascalTokenKind.Keyword) or not Tokens[Index].IsKeyword('except') then
      Continue;
    // Zwischen except und end steht nichts außer Kommentaren und Direktiven.
    Next := Index + 1;
    Commented := False;
    while (Next <= High(Tokens)) and IsTrivia(Tokens[Next]) do
    begin
      if Tokens[Next].Kind = TPascalTokenKind.Comment then
        Commented := True;
      Inc(Next);
    end;
    if (Next > High(Tokens)) or not Tokens[Next].IsKeyword('end') or Commented then
      Continue;
    Indent := LineIndent(AContext.Text, Tokens[Index].StartPos.Line);
    AReport.Add(TokenRange(Tokens[Index]), 'Leerer except-Block verschluckt jede Ausnahme; behandeln, ' +
      'weiterwerfen oder mit einem Kommentar begründen', TRuleConfidence.High,
      [TRuleFix.Create('raise; einfügen', [TRuleEdit.Create(TTextRange.Create(Tokens[Index].EndPos,
        Tokens[Index].EndPos), LineBreakOf(AContext.Text) + Indent + '  raise;')])]);
  end;
end;

{ Interface-Deklarationen }

type
  /// <summary>Interface-Typ der Datei mit seiner GUID ('' ohne).</summary>
  TInterfaceDeclaration = record
    Name: string;
    NameToken: Integer;
    /// <summary>Token, hinter dem die GUID-Zeile eingefügt wird: interface bzw. die schließende Klammer der Vorfahren.</summary>
    HeaderEnd: Integer;
    Guid: string;
    GuidToken: Integer;
  end;

function InterfaceDeclarations(const ATokens: TArray<TPascalToken>): TArray<TInterfaceDeclaration>;
var
  Index, Equals, Name, Next: Integer;
  Declaration: TInterfaceDeclaration;
begin
  Result := nil;
  for Index := 0 to High(ATokens) do
  begin
    if not (ATokens[Index].IsKeyword('interface') or ATokens[Index].IsKeyword('dispinterface')) then
      Continue;
    // "IFoo = interface": vor dem Schlüsselwort steht "=", davor der Name.
    Equals := PreviousCode(ATokens, Index);
    if (Equals < 0) or not ATokens[Equals].IsSymbol('=') then
      Continue;
    Name := PreviousCode(ATokens, Equals);
    if (Name < 0) or (ATokens[Name].Kind <> TPascalTokenKind.Identifier) then
      Continue;
    Declaration := Default(TInterfaceDeclaration);
    Declaration.Name := ATokens[Name].Text;
    Declaration.NameToken := Name;
    Declaration.HeaderEnd := Index;
    Declaration.GuidToken := -1;
    Next := NextCode(ATokens, Index + 1);
    // Vorwärtsdeklaration "IFoo = interface;" hat keine GUID.
    if (Next <= High(ATokens)) and ATokens[Next].IsSymbol(';') then
      Continue;
    if (Next <= High(ATokens)) and ATokens[Next].IsSymbol('(') then
    begin
      while (Next <= High(ATokens)) and not ATokens[Next].IsSymbol(')') do
        Inc(Next);
      Declaration.HeaderEnd := Next;
      Next := NextCode(ATokens, Next + 1);
    end;
    if (Next + 2 <= High(ATokens)) and ATokens[Next].IsSymbol('[') and
      (ATokens[Next + 1].Kind = TPascalTokenKind.StringLiteral) then
    begin
      Declaration.Guid := UpperCase(AnsiDequotedStr(ATokens[Next + 1].Text, ''''));
      Declaration.GuidToken := Next + 1;
    end
    else if (Next + 2 <= High(ATokens)) and ATokens[Next].IsSymbol('[') then
      // GUID über eine Konstante: vorhanden, aber nicht vergleichbar.
      Declaration.GuidToken := Next;
    Result := Result + [Declaration];
  end;
end;

{ TInterfaceGuidRule }

function TInterfaceGuidRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('interface-guid', TRuleSeverity.Warning, 'Interface ohne GUID');
end;

/// <summary>Wird AName mit Supports, as oder QueryInterface abgefragt?</summary>
function IsQueried(const ATokens: TArray<TPascalToken>; const AName: string): Boolean;
var
  Index, Previous, Inner: Integer;
begin
  for Index := 0 to High(ATokens) do
  begin
    if (ATokens[Index].Kind <> TPascalTokenKind.Identifier) or not SameText(ATokens[Index].Text, AName) then
      Continue;
    Previous := PreviousCode(ATokens, Index);
    if (Previous >= 0) and ATokens[Previous].IsKeyword('as') then
      Exit(True);
    // Supports(X, IFoo, …) bzw. QueryInterface(IFoo, …): der Name steht in der Argumentliste.
    for Inner := Index - 1 downto Max(0, Index - 8) do
      if (ATokens[Inner].Kind = TPascalTokenKind.Identifier) and
        (SameText(ATokens[Inner].Text, 'Supports') or SameText(ATokens[Inner].Text, 'QueryInterface')) then
        Exit(True)
      else if ATokens[Inner].IsSymbol(';') then
        Break;
  end;
  Result := False;
end;

procedure TInterfaceGuidRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Tokens: TArray<TPascalToken>;
  Declaration: TInterfaceDeclaration;
  Confidence: TRuleConfidence;
  Indent: string;
begin
  if AContext.Tree = nil then
    Exit;
  Tokens := AContext.Tree.Tokens;
  for Declaration in InterfaceDeclarations(Tokens) do
  begin
    if Declaration.GuidToken >= 0 then
      Continue;
    if IsQueried(Tokens, Declaration.Name) then
      Confidence := TRuleConfidence.High
    else
      Confidence := TRuleConfidence.Low;
    Indent := LineIndent(AContext.Text, Tokens[Declaration.NameToken].StartPos.Line);
    AReport.Add(TokenRange(Tokens[Declaration.NameToken]), Format('Interface %s hat keine GUID; Supports, as ' +
      'und QueryInterface brauchen eine', [Declaration.Name]), Confidence,
      [TRuleFix.Create('GUID einfügen', [TRuleEdit.Create(TTextRange.Create(Tokens[Declaration.HeaderEnd].EndPos,
        Tokens[Declaration.HeaderEnd].EndPos), LineBreakOf(AContext.Text) + Indent + '  ' + GuidLine)], True)]);
  end;
end;

{ TDuplicateInterfaceGuidRule }

function TDuplicateInterfaceGuidRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('duplicate-interface-guid', TRuleSeverity.Error,
    'Zwei Interfaces mit derselben GUID');
end;

procedure TDuplicateInterfaceGuidRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Tokens: TArray<TPascalToken>;
  Declarations: TArray<TInterfaceDeclaration>;
  Index, Other: Integer;
  Token: TPascalToken;
begin
  if AContext.Tree = nil then
    Exit;
  Tokens := AContext.Tree.Tokens;
  Declarations := InterfaceDeclarations(Tokens);
  for Index := 0 to High(Declarations) do
  begin
    if Declarations[Index].Guid = '' then
      Continue;
    for Other := 0 to High(Declarations) do
      if (Other <> Index) and (Declarations[Other].Guid = Declarations[Index].Guid) then
      begin
        Token := Tokens[Declarations[Index].GuidToken];
        AReport.Add(TokenRange(Token), Format('%s hat dieselbe GUID wie %s; Supports und as verwechseln die ' +
          'beiden', [Declarations[Index].Name, Declarations[Other].Name]), TRuleConfidence.High,
          [TRuleFix.Create('Neue GUID erzeugen', [TRuleEdit.Create(TokenRange(Token),
            Copy(GuidLine, 2, Length(GuidLine) - 2))])]);
        Break;
      end;
  end;
end;

{ TFileHeaderRule }

function TFileHeaderRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('file-header', TRuleSeverity.Hint, 'Dateikopf fehlt oder weicht ab', True);
end;

class function TFileHeaderRule.Template(const AOptions: string): string;
var
  Value: TJSONValue;
begin
  Result := '';
  if Trim(AOptions) = '' then
    Exit;
  Value := TJSONObject.ParseJSONValue(AOptions);
  try
    if Value is TJSONObject then
      TJSONObject(Value).TryGetValue<string>('template', Result);
  finally
    Value.Free;
  end;
end;

procedure TFileHeaderRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Header, Text, LineBreak: string;
begin
  Header := Template(AContext.Options);
  if Header = '' then
    Exit;
  LineBreak := LineBreakOf(AContext.Text);
  Header := StringReplace(StringReplace(Header, #13#10, #10, [rfReplaceAll]), #10, LineBreak, [rfReplaceAll]);
  Text := AContext.Text;
  if (Text <> '') and (Text[1] = #$FEFF) then
    Delete(Text, 1, 1);
  if StartsStr(Header, Text) then
    Exit;
  AReport.Add(TTextRange.Create(0, 0, 0, 0), 'Der Dateikopf entspricht nicht der Vorlage', TRuleConfidence.High,
    [TRuleFix.Create('Dateikopf einfügen', [TRuleEdit.Create(TTextRange.Create(0, 0, 0, 0), Header + LineBreak)])]);
end;

{ THardcodedStringRule }

function THardcodedStringRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('hardcoded-string', TRuleSeverity.Hint, 'Text im Code statt resourcestring',
    True);
end;

/// <summary>Sieht der Literalinhalt nach Text für Menschen aus: mindestens zwei Wörter mit Buchstaben?</summary>
function LooksLikeText(const AValue: string): Boolean;
var
  Index, Letters: Integer;
begin
  Letters := 0;
  for Index := 1 to Length(AValue) do
    if AValue[Index].IsLetter then
      Inc(Letters);
  Result := (Letters >= 3) and (Pos(' ', Trim(AValue)) > 0);
end;

procedure THardcodedStringRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Tokens: TArray<TPascalToken>;
  Index, Depth: Integer;
begin
  if AContext.Tree = nil then
    Exit;
  Tokens := AContext.Tree.Tokens;
  Depth := 0;
  for Index := 0 to High(Tokens) do
  begin
    if Tokens[Index].Kind = TPascalTokenKind.Keyword then
    begin
      if Tokens[Index].IsKeyword('begin') then
        Inc(Depth)
      else if (Depth > 0) and (Tokens[Index].IsKeyword('try') or Tokens[Index].IsKeyword('case') or
        Tokens[Index].IsKeyword('asm')) then
        Inc(Depth)
      else if (Depth > 0) and Tokens[Index].IsKeyword('end') then
        Dec(Depth);
      Continue;
    end;
    // Nur Anweisungen: Konstanten- und resourcestring-Abschnitte stehen außerhalb von begin … end.
    if (Depth = 0) or (Tokens[Index].Kind <> TPascalTokenKind.StringLiteral) then
      Continue;
    if LooksLikeText(AnsiDequotedStr(Tokens[Index].Text, '''')) then
      AReport.Add(TokenRange(Tokens[Index]), 'Text im Code; für Übersetzungen in einen resourcestring auslagern',
        TRuleConfidence.Low);
  end;
end;

procedure RegisterGeneralRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TEmptyExceptRule.Create);
  ARegistry.Register(TInterfaceGuidRule.Create);
  ARegistry.Register(TDuplicateInterfaceGuidRule.Create);
  ARegistry.Register(TFileHeaderRule.Create);
  ARegistry.Register(THardcodedStringRule.Create);
end;

end.
