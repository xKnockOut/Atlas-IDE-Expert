unit Atlas.Common.Pascal.CallSites;

// Offener Aufruf vor einer Stelle: die innerste offene Klammer hinter einem Bezeichner, der aktive Parameter
// (Kommas auf derselben Ebene) und die Token der bisherigen Argumente (#498). Ohne Namensauflösung; für
// Parameterhilfe, erwartete Typen und Formatroutinen.

interface

uses
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree;

type
  TPascalCallSite = record
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

  TPascalCallSites = class
  public
    /// <summary>Innerster offener Aufruf vor APosition; Found False ohne.</summary>
    class function At(ATree: TSyntaxTree; const APosition: TTextPosition): TPascalCallSite; static;
  end;

implementation

uses
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.TokenCursor;

const
  /// <summary>Schlüsselwörter, an denen die Suche nach der offenen Klammer endet.</summary>
  cStatementKeywords: array[0..4] of string = ('begin', 'end', 'then', 'do', 'var');

type
  /// <summary>Rückwärtssuche nach der innersten offenen Aufrufklammer; sammelt die Argumente (#498).</summary>
  TCallScan = record
    Tokens: TArray<TPascalToken>;
    /// <summary>Letztes Token vor der Position.</summary>
    Last: Integer;
    Depth: Integer;
    Commas: Integer;
    /// <summary>Letztes Token des Arguments links vom nächsten Komma.</summary>
    SpanEnd: Integer;
    Firsts: TArray<Integer>;
    Lasts: TArray<Integer>;
    procedure AddArgument(AFirst: Integer);
    function Opening(AIndex: Integer; var ASite: TPascalCallSite): Boolean;
    function Separator(AIndex: Integer): Boolean;
    /// <summary>Verarbeitet das Token AIndex; True beendet die Suche.</summary>
    function Step(AIndex: Integer; var ASite: TPascalCallSite): Boolean;
  end;

/// <summary>; oder ein Schlüsselwort, hinter dem kein offener Aufruf mehr stehen kann.</summary>
function EndsStatement(const AToken: TPascalToken): Boolean;
begin
  Result := AToken.IsSymbol(';') or IsKeywordIn(AToken, cStatementKeywords);
end;

{ TCallScan }

procedure TCallScan.AddArgument(AFirst: Integer);
begin
  Firsts := TArray<Integer>.Create(AFirst) + Firsts;
  Lasts := TArray<Integer>.Create(SpanEnd) + Lasts;
end;

function TCallScan.Opening(AIndex: Integer; var ASite: TPascalCallSite): Boolean;
var
  mPrevious: Integer;
begin
  Result := False;
  if Depth > 0 then
  begin
    Dec(Depth);
    Exit;
  end;
  mPrevious := PreviousCode(Tokens, AIndex);
  if Tokens[AIndex].IsSymbol('(') and (mPrevious >= 0) and (Tokens[mPrevious].Kind = TPascalTokenKind.Identifier) then
  begin
    AddArgument(AIndex + 1);
    ASite.NamePosition := Tokens[mPrevious].StartPos;
    ASite.ActiveParameter := Commas;
    ASite.Found := True;
    ASite.ArgumentFirst := Firsts;
    ASite.ArgumentLast := Lasts;
    Exit(True);
  end;
  // Klammer um einen Ausdruck oder eine Menge: sie ist selbst ein Argument des äußeren Aufrufs.
  Commas := 0;
  Firsts := nil;
  Lasts := nil;
  SpanEnd := Last;
end;

function TCallScan.Separator(AIndex: Integer): Boolean;
begin
  Result := False;
  if Tokens[AIndex].IsSymbol(',') then
  begin
    Inc(Commas);
    AddArgument(AIndex + 1);
    SpanEnd := AIndex - 1;
  end
  else
  begin
    Result := EndsStatement(Tokens[AIndex]);
  end;
end;

function TCallScan.Step(AIndex: Integer; var ASite: TPascalCallSite): Boolean;
var
  mToken: TPascalToken;
begin
  Result := False;
  mToken := Tokens[AIndex];
  if IsTrivia(mToken) then
  begin
    Exit;
  end;
  if mToken.IsSymbol(')') or mToken.IsSymbol(']') then
  begin
    Inc(Depth);
  end
  else if mToken.IsSymbol('(') or mToken.IsSymbol('[') then
  begin
    Result := Opening(AIndex, ASite);
  end
  else if Depth = 0 then
  begin
    Result := Separator(AIndex);
  end;
end;

{ TPascalCallSites }

class function TPascalCallSites.At(ATree: TSyntaxTree; const APosition: TTextPosition): TPascalCallSite;
var
  mScan: TCallScan;
  mIndex: Integer;
begin
  Result := Default(TPascalCallSite);
  if ATree = nil then
  begin
    Exit;
  end;
  mScan := Default(TCallScan);
  mScan.Tokens := ATree.Tokens;
  mScan.Last := TokenBeforePosition(mScan.Tokens, APosition);
  // Argumente rückwärts gesammelt (#498).
  mScan.SpanEnd := mScan.Last;
  for mIndex := mScan.Last downto 0 do
  begin
    if mScan.Step(mIndex, Result) then
    begin
      Break;
    end;
  end;
end;

end.
