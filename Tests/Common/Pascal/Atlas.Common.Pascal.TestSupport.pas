unit Atlas.Common.Pascal.TestSupport;

// Gemeinsame Hilfen der Parsertests: Knoten und Token suchen, Namen von Kindknoten, Syntaxfehler als Text und
// Symbole des Index.

interface

uses
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Index.Contract;

type
  TPascalTest = record
  public
    /// <summary>Erster Knoten der Art AKind (mit dem Namen AName, '' = jeder) in ANode und darunter; sonst nil.
    /// </summary>
    class function Find(ANode: TSyntaxNode; AKind: TSyntaxKind; const AName: string): TSyntaxNode; static;
    /// <summary>Namen der direkten Kindknoten der Art AKind, durch Komma getrennt.</summary>
    class function ChildNames(ANode: TSyntaxNode; AKind: TSyntaxKind): string; static;
    /// <summary>Syntaxfehler von AText als "Zeile:Zeichen Meldung; " je Fehler.</summary>
    class function Diagnostics(const AText: string): string; static;
    /// <summary>AUnit enthält das Symbol AName im Container AContainer.</summary>
    class function HasSymbol(const AUnit: TUnitIndex; const AContainer, AName: string): Boolean; static;
    /// <summary>Index des AOccurrence-ten Tokens (ab 1) mit dem Text AText; -1 ohne.</summary>
    class function TokenOf(const ATokens: TArray<TPascalToken>; const AText: string; AOccurrence: Integer): Integer;
      static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Pascal.TreeCache;

{ TPascalTest }

class function TPascalTest.Find(ANode: TSyntaxNode; AKind: TSyntaxKind; const AName: string): TSyntaxNode;
var
  mIndex: Integer;
begin
  if (ANode.Kind = AKind) and ((AName = '') or SameText(ANode.Name, AName)) then
  begin
    Exit(ANode);
  end;
  for mIndex := 0 to ANode.ChildCount - 1 do
  begin
    Result := Find(ANode[mIndex], AKind, AName);
    if Result <> nil then
    begin
      Exit;
    end;
  end;
  Result := nil;
end;

class function TPascalTest.ChildNames(ANode: TSyntaxNode; AKind: TSyntaxKind): string;
var
  mIndex: Integer;
begin
  Result := '';
  for mIndex := 0 to ANode.ChildCount - 1 do
  begin
    if ANode[mIndex].Kind = AKind then
    begin
      if Result <> '' then
      begin
        Result := Result + ',';
      end;
      Result := Result + ANode[mIndex].Name;
    end;
  end;
end;

class function TPascalTest.Diagnostics(const AText: string): string;
var
  mTree: TSyntaxTree;
  mDiagnostic: TSyntaxDiagnostic;
begin
  Result := '';
  mTree := TSyntaxTreeCache.Parse(AText);
  try
    for mDiagnostic in mTree.Diagnostics do
    begin
      Result := Result + Format('%d:%d %s; ', [mDiagnostic.StartPos.Line, mDiagnostic.StartPos.Character,
        mDiagnostic.Message]);
    end;
  finally
    mTree.Free;
  end;
end;

class function TPascalTest.HasSymbol(const AUnit: TUnitIndex; const AContainer, AName: string): Boolean;
var
  mSymbol: TIndexSymbol;
begin
  for mSymbol in AUnit.Symbols do
  begin
    if SameText(mSymbol.Container, AContainer) and SameText(mSymbol.Name, AName) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

class function TPascalTest.TokenOf(const ATokens: TArray<TPascalToken>; const AText: string; AOccurrence: Integer): Integer;
var
  mIndex, mCount: Integer;
begin
  mCount := 0;
  for mIndex := 0 to High(ATokens) do
  begin
    if ATokens[mIndex].Text = AText then
    begin
      Inc(mCount);
      if mCount = AOccurrence then
      begin
        Exit(mIndex);
      end;
    end;
  end;
  Result := -1;
end;

end.
