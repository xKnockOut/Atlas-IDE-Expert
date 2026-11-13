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
  Atlas.Common.Semantics.ControlFlow.Signatures,
  Atlas.Common.Semantics.NameResolver;

type
  TResolvedSignatures = class
  public const
    /// <summary>Typumwandlungen, die das Argument nur lesen.</summary>
    cValueCasts: array[0..9] of string = ('PChar', 'PWideChar', 'PAnsiChar', 'string', 'AnsiString', 'UTF8String',
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
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Editing.ChangeSignature;

/// <summary>Token, das an AOffset beginnt; -1 ohne.</summary>
function TokenStartingAt(const ATokens: TArray<TPascalToken>; AOffset: Integer): Integer;
var
  mLow_, mHigh_, mMiddle: Integer;
begin
  mLow_ := 0;
  mHigh_ := High(ATokens);
  while mLow_ <= mHigh_ do
  begin
    mMiddle := (mLow_ + mHigh_) div 2;
    if ATokens[mMiddle].Offset < AOffset then
    begin
      mLow_ := mMiddle + 1;
    end
    else if ATokens[mMiddle].Offset > AOffset then
    begin
      mHigh_ := mMiddle - 1;
    end
    else
    begin
      Exit(mMiddle);
    end;
  end;
  Result := -1;
end;

class function TResolvedSignatures.SignatureModes(const ASignature: string; out AModes: TArray<string>): Boolean;
var
  mOpen, mClose, mDepth, mIndex: Integer;
  mParameter: TSignatureParameter;
begin
  AModes := nil;
  mOpen := Pos('(', ASignature);
  mClose := 0;
  mDepth := 0;
  if mOpen > 0 then
  begin
    for mIndex := mOpen to Length(ASignature) do
    begin
      if ASignature[mIndex] = '(' then
      begin
        Inc(mDepth);
      end
      else if ASignature[mIndex] = ')' then
      begin
        Dec(mDepth);
        if mDepth = 0 then
        begin
          mClose := mIndex;
          Break;
        end;
      end;
    end;
  end;
  Result := mClose > 0;
  if Result then
  begin
    for mParameter in TChangeSignature.ParseParameters(Copy(ASignature, mOpen + 1, mClose - mOpen - 1)) do
    begin
      AModes := AModes + [LowerCase(Trim(mParameter.Modifier))];
    end;
  end;
end;

/// <summary>Anfang des Namens der aufgerufenen Routine ACallee; False bei anderer Knotenart.</summary>
function CalleeOffset(ACallee: TSyntaxNode; out AOffset: Integer): Boolean;
begin
  Result := True;
  if ACallee.Kind = TSyntaxKind.Identifier then
  begin
    AOffset := ACallee.StartOffset;
  end
  else if ACallee.Kind = TSyntaxKind.MemberAccess then
  begin
    AOffset := ACallee.EndOffset - Length(ACallee.Name);
  end
  else
  begin
    AOffset := -1;
    Result := False;
  end;
end;

/// <summary>Art des Parameters AArgument eines aufgelösten Kandidaten; Unknown, wenn nicht sicher.</summary>
function SymbolMode(const ASymbol: TResolvedSymbol; AArgument: Integer): TFlowArgumentMode;
var
  mModes: TArray<string>;
begin
  if not ASymbol.Found then
  begin
    Result := TFlowArgumentMode.Unknown;
  end
  else if ASymbol.IsType then
  begin
    Result := TFlowArgumentMode.Value;
  end
  // Weitere Varianten derselben Datei: nicht sicher, welche gemeint ist.
  else if (Length(ASymbol.Overloads) > 0) or (Length(ASymbol.VariantParams) > 1) or
    not TResolvedSignatures.SignatureModes(ASymbol.Signature, mModes) or (AArgument >= Length(mModes)) then
  begin
    Result := TFlowArgumentMode.Unknown;
  end
  else if mModes[AArgument] = 'out' then
  begin
    Result := TFlowArgumentMode.Output;
  end
  else if mModes[AArgument] = 'var' then
  begin
    Result := TFlowArgumentMode.Reference;
  end
  else
  begin
    Result := TFlowArgumentMode.Value;
  end;
end;

/// <summary>Gemeinsame Art aller gleich guten Kandidaten; Unknown, wenn sie nicht übereinstimmen.</summary>
function CommonMode(const ASymbols: TArray<TResolvedSymbol>; AArgument: Integer): TFlowArgumentMode;
var
  mIndex: Integer;
  mFound: TFlowArgumentMode;
begin
  Result := TFlowArgumentMode.Unknown;
  for mIndex := 0 to High(ASymbols) do
  begin
    mFound := SymbolMode(ASymbols[mIndex], AArgument);
    if (mFound = TFlowArgumentMode.Unknown) or ((mIndex > 0) and (mFound <> Result)) then
    begin
      Exit(TFlowArgumentMode.Unknown);
    end;
    Result := mFound;
  end;
end;

class function TResolvedSignatures.Mode(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName: string;
  ACall: TSyntaxNode; AArgument: Integer): TFlowArgumentMode;
var
  mCallee: TSyntaxNode;
  mOffset, mToken: Integer;
begin
  Result := TFlowArgumentMode.Unknown;
  if (ACall = nil) or (ACall.ChildCount = 0) or (ATree = nil) then
  begin
    Exit;
  end;
  mCallee := ACall[0];
  if (mCallee.Kind = TSyntaxKind.Identifier) and MatchText(mCallee.Name, cValueCasts) then
  begin
    Exit(TFlowArgumentMode.Value);
  end;
  if (AResolver = nil) or not CalleeOffset(mCallee, mOffset) then
  begin
    Exit;
  end;
  mToken := TokenStartingAt(ATree.Tokens, mOffset);
  if (mToken >= 0) and SameText(ATree.Tokens[mToken].Text, mCallee.Name) then
  begin
    // Alle gleich guten Kandidaten: Ist die Überladung nicht eindeutig, zählt die Art nur, wenn alle übereinstimmen.
    Result := CommonMode(AResolver.ResolveAll(ATree, AFileName, ATree.Tokens[mToken].StartPos), AArgument);
  end;
end;

class function TResolvedSignatures.Lookup(AResolver: TNameResolver; ATree: TSyntaxTree;
  const AFileName: string): TFlowSignatureLookup;
var
  mLocal: TFlowSignatureLookup;
  mResolver: TNameResolver;
  mTree: TSyntaxTree;
  mFileName: string;
begin
  mLocal := nil;
  if ATree <> nil then
  begin
    mLocal := TFlowSignatures.FromTree(ATree.Root);
  end;
  mResolver := AResolver;
  mTree := ATree;
  mFileName := AFileName;
  Result :=
    function(ACall: TSyntaxNode; AArgument: Integer): TFlowArgumentMode
    begin
      Result := TFlowArgumentMode.Unknown;
      if Assigned(mLocal) then
      begin
        Result := mLocal(ACall, AArgument);
      end;
      if Result = TFlowArgumentMode.Unknown then
      begin
        Result := TResolvedSignatures.Mode(mResolver, mTree, mFileName, ACall, AArgument);
      end;
    end;
end;

end.
