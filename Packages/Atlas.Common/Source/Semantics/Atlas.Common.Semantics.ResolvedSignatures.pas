unit Atlas.Common.Semantics.ResolvedSignatures;

// Übergabeart von Argumenten über die Namensauflösung (#712), gemeinsam für
// Prüfregeln und Editorfunktionen: Methoden (Obj.Foo(X)), Routinen anderer
// Units und Typumwandlungen. TFlowSignatures.FromTree kennt nur Routinen
// derselben Datei und die Standardroutinen; Lookup fragt erst dort und nur bei
// Unknown die Namensauflösung. Wählt sie die Überladung nicht eindeutig
// (ResolveAll mit mehreren Kandidaten), zählt die Art nur, wenn alle
// Kandidaten übereinstimmen; sonst bleibt es Unknown.

interface

uses
  System.SysUtils,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Semantics.ControlFlow,
  Atlas.Common.Semantics.NameResolver;

type
  TResolvedSignatures = class
  public const
    /// <summary>Typumwandlungen, die das Argument nur lesen.</summary>
    ValueCasts: array[0..9] of string = ('PChar', 'PWideChar', 'PAnsiChar', 'string', 'AnsiString', 'UTF8String',
      'RawByteString', 'WideString', 'UnicodeString', 'Pointer');
  public
    /// <summary>Modifizierer der Parameter einer Signatur je Name in Kleinbuchstaben ('' bei Wertparametern);
    /// False ohne Klammern.</summary>
    class function SignatureModes(const ASignature: string; out AModes: TArray<string>): Boolean; static;
    /// <summary>Übergabeart über AResolver (nil: Unknown); ACall ist ein Knoten der Art Call aus ATree.</summary>
    class function Mode(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName: string; ACall: TSyntaxNode;
      AArgument: Integer): TFlowArgumentMode; static;
    /// <summary>TFlowSignatures.FromTree, bei Unknown über AResolver (nil: nur der Baum). AResolver muss leben,
    /// solange das Ergebnis benutzt wird.</summary>
    class function Lookup(AResolver: TNameResolver; ATree: TSyntaxTree;
      const AFileName: string): TFlowSignatureLookup; static;
  end;

implementation

uses
  System.StrUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Editing.ChangeSignature;

/// <summary>Token, das an AOffset beginnt; -1 ohne.</summary>
function TokenStartingAt(const ATokens: TArray<TPascalToken>; AOffset: Integer): Integer;
var
  Low_, High_, Middle: Integer;
begin
  Low_ := 0;
  High_ := High(ATokens);
  while Low_ <= High_ do
  begin
    Middle := (Low_ + High_) div 2;
    if ATokens[Middle].Offset < AOffset then
      Low_ := Middle + 1
    else if ATokens[Middle].Offset > AOffset then
      High_ := Middle - 1
    else
      Exit(Middle);
  end;
  Result := -1;
end;

class function TResolvedSignatures.SignatureModes(const ASignature: string; out AModes: TArray<string>): Boolean;
var
  Open, Close, Depth, Index: Integer;
  Parameter: TSignatureParameter;
begin
  AModes := nil;
  Open := Pos('(', ASignature);
  Close := 0;
  Depth := 0;
  if Open > 0 then
    for Index := Open to Length(ASignature) do
      if ASignature[Index] = '(' then
        Inc(Depth)
      else if ASignature[Index] = ')' then
      begin
        Dec(Depth);
        if Depth = 0 then
        begin
          Close := Index;
          Break;
        end;
      end;
  Result := Close > 0;
  if Result then
    for Parameter in TChangeSignature.ParseParameters(Copy(ASignature, Open + 1, Close - Open - 1)) do
      AModes := AModes + [LowerCase(Trim(Parameter.Modifier))];
end;

class function TResolvedSignatures.Mode(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName: string;
  ACall: TSyntaxNode; AArgument: Integer): TFlowArgumentMode;
var
  Callee: TSyntaxNode;
  Offset, Token, Index: Integer;
  Symbols: TArray<TResolvedSymbol>;
  Symbol: TResolvedSymbol;
  Modes: TArray<string>;
  Found: TFlowArgumentMode;
begin
  Result := TFlowArgumentMode.Unknown;
  if (ACall = nil) or (ACall.ChildCount = 0) or (ATree = nil) then
    Exit;
  Callee := ACall[0];
  if (Callee.Kind = TSyntaxKind.Identifier) and MatchText(Callee.Name, ValueCasts) then
    Exit(TFlowArgumentMode.Value);
  if AResolver = nil then
    Exit;
  if Callee.Kind = TSyntaxKind.Identifier then
    Offset := Callee.StartOffset
  else if Callee.Kind = TSyntaxKind.MemberAccess then
    Offset := Callee.EndOffset - Length(Callee.Name)
  else
    Exit;
  Token := TokenStartingAt(ATree.Tokens, Offset);
  if (Token < 0) or not SameText(ATree.Tokens[Token].Text, Callee.Name) then
    Exit;
  // Alle gleich guten Kandidaten: Ist die Überladung nicht eindeutig, zählt die Art nur, wenn alle übereinstimmen.
  Symbols := AResolver.ResolveAll(ATree, AFileName, ATree.Tokens[Token].StartPos);
  for Index := 0 to High(Symbols) do
  begin
    Symbol := Symbols[Index];
    if not Symbol.Found then
      Exit(TFlowArgumentMode.Unknown);
    if Symbol.IsType then
      Found := TFlowArgumentMode.Value
    // Weitere Varianten derselben Datei: nicht sicher, welche gemeint ist.
    else if (Length(Symbol.Overloads) > 0) or (Length(Symbol.VariantParams) > 1) or
      not SignatureModes(Symbol.Signature, Modes) or (AArgument >= Length(Modes)) then
      Exit(TFlowArgumentMode.Unknown)
    else if Modes[AArgument] = 'out' then
      Found := TFlowArgumentMode.Output
    else if Modes[AArgument] = 'var' then
      Found := TFlowArgumentMode.Reference
    else
      Found := TFlowArgumentMode.Value;
    if (Index > 0) and (Found <> Result) then
      Exit(TFlowArgumentMode.Unknown);
    Result := Found;
  end;
end;

class function TResolvedSignatures.Lookup(AResolver: TNameResolver; ATree: TSyntaxTree;
  const AFileName: string): TFlowSignatureLookup;
var
  Local: TFlowSignatureLookup;
  Resolver: TNameResolver;
  Tree: TSyntaxTree;
  FileName: string;
begin
  Local := nil;
  if ATree <> nil then
    Local := TFlowSignatures.FromTree(ATree.Root);
  Resolver := AResolver;
  Tree := ATree;
  FileName := AFileName;
  Result :=
    function(ACall: TSyntaxNode; AArgument: Integer): TFlowArgumentMode
    begin
      Result := TFlowArgumentMode.Unknown;
      if Assigned(Local) then
        Result := Local(ACall, AArgument);
      if Result = TFlowArgumentMode.Unknown then
        Result := TResolvedSignatures.Mode(Resolver, Tree, FileName, ACall, AArgument);
    end;
end;

end.
