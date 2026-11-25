unit Atlas.Common.Pascal.UsesClauses;

// uses-, contains- und requires-Listen lesen: Namen, Positionen, Abschnitt,
// Name der eigenen Unit, Testframework. Nur Lesen über den Token; Ändern der
// Listen (Eintragen, Aufräumen, Sortieren) liegt bei den Befehlen, die es brauchen.

interface

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Contract;

type
  /// <summary>Art der Liste: uses bindet ein, contains (Package) nimmt auf, requires (Package) braucht ein
  /// Package.</summary>
  TUsesListKind = (UsesList, ContainsList, RequiresList);

  /// <summary>Eintrag einer uses-, contains- oder requires-Liste mit Position (#183).</summary>
  TUsesReference = record
    Name: string;
    Range: TTextRange;
    List: TUsesListKind;
    /// <summary>Steht im interface-Teil einer Unit (#268); in Programmen, Packages und im
    /// implementation-Teil False.</summary>
    InInterface: Boolean;
  end;

  /// <summary>Eine uses-Liste (#284).</summary>
  TUsesClauseInfo = record
    /// <summary>Token-Index von "uses" und vom abschließenden Semikolon.</summary>
    UsesIndex: Integer;
    Semicolon: Integer;
    Names: TArray<string>;
    /// <summary>Im interface einer Unit.</summary>
    InInterface: Boolean;
    /// <summary>Ohne Direktiven und //-Kommentare; nur solche Listen werden umgeschrieben.</summary>
    Plain: Boolean;
  end;

  /// <summary>Liest die uses-Listen einer Unit, eines Programms oder Packages.</summary>
  TPascalUses = class
  public
    /// <summary>Alle uses-Listen (nicht requires/contains) in Reihenfolge.</summary>
    class function Clauses(const ATokens: TArray<TPascalToken>): TArray<TUsesClauseInfo>; static;
    /// <summary>Liegt AOffset zwischen uses und Semikolon einer der Listen AClauses?</summary>
    class function InClause(const ATokens: TArray<TPascalToken>; const AClauses: TArray<TUsesClauseInfo>;
      AOffset: Integer): Boolean; static;
    /// <summary>Alle Unit-Namen aus den uses-Listen (interface und implementation).</summary>
    class function UsedUnits(const ATokens: TArray<TPascalToken>): TArray<string>; static;
    /// <summary>Wie UsedUnits für den Quelltext AText.</summary>
    class function UsedUnitsOf(const AText: string): TArray<string>; static;
    /// <summary>True, wenn die Unit ein Test-Framework einbindet (DUnitX.TestFramework, TestFramework
    /// oder TestInsight.*).</summary>
    class function IsTestUnit(const ATokens: TArray<TPascalToken>): Boolean; static;
    /// <summary>Nennt AUsed ein Testframework (DUnitX.TestFramework, TestFramework, TestInsight.*)? Wie
    /// IsTestUnit, aber aus den uses-Listen des Index statt aus dem Quelltext.</summary>
    class function UsesTestFramework(const AUsed: TArray<string>): Boolean; static;
    /// <summary>Alle Einträge aus uses, contains und requires mit Position, in Quelltextreihenfolge.</summary>
    class function References(const ATokens: TArray<TPascalToken>): TArray<TUsesReference>; static;
    /// <summary>Name der eigenen Unit bzw. des Programms; '' wenn unbekannt.</summary>
    class function OwnName(const ATokens: TArray<TPascalToken>): string; static;
    /// <summary>True, wenn AUnitName eingebunden ist, auch über einen der Namespaces.</summary>
    class function IsUsed(const AUsed: TArray<string>; const AUnitName: string;
      const ANamespaces: TArray<string>): Boolean; static;
    /// <summary>Index des Abschnittsworts (interface/implementation) bzw. des Semikolons hinter dem Programmkopf
    /// für AOffset; -1, wenn nicht vorhanden.</summary>
    class function SectionStart(const ATokens: TArray<TPascalToken>; AOffset: Integer): Integer; static;
    /// <summary>Liest die Namen der Liste ab dem Schlüsselwort an AUses nach ANames; Index des Semikolons, -1
    /// ohne.</summary>
    class function ReadNames(const ATokens: TArray<TPascalToken>; AUses: Integer; var ANames: TArray<string>):
      Integer; static;
    /// <summary>True, wenn die Liste zwischen AFirst und ALast keine Direktive und keinen //-Kommentar enthält.
    /// </summary>
    class function IsPlainList(const ATokens: TArray<TPascalToken>; AFirst, ALast: Integer): Boolean; static;
    /// <summary>ATokens ohne die Token, die in einem der Bereiche AInactive beginnen (inaktive Zweige, #621);
    /// bei AInactive = nil ATokens selbst.</summary>
    class function ActiveTokens(const ATokens: TArray<TPascalToken>;
      const AInactive: TArray<TTextRange>): TArray<TPascalToken>; static;
  end;

implementation

uses
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Pascal.TokenCursor;

/// <summary>Index des Semikolons, das die Anweisung ab AIndex abschließt; -1 ohne.</summary>
function SemicolonAfter(const ATokens: TArray<TPascalToken>; AIndex: Integer): Integer;
begin
  Result := AIndex;
  while Result <= High(ATokens) do
  begin
    if ATokens[Result].IsSymbol(';') then
    begin
      Exit;
    end;
    Inc(Result);
  end;
  Result := -1;
end;

/// <summary>Erstes Token (nicht Trivia); -1 bei leerem Text.</summary>
function FirstIndex(const ATokens: TArray<TPascalToken>): Integer;
begin
  Result := NextCodeAfter(ATokens, -1);
  if Result > High(ATokens) then
  begin
    Result := -1;
  end;
end;

class function TPascalUses.SectionStart(const ATokens: TArray<TPascalToken>; AOffset: Integer): Integer;
var
  mFirst, mHeaderEnd, mIndex, mInterface_, mImplementation_: Integer;
begin
  Result := -1;
  mFirst := FirstIndex(ATokens);
  if mFirst < 0 then
  begin
    Exit;
  end;
  mHeaderEnd := SemicolonAfter(ATokens, mFirst);
  if mHeaderEnd < 0 then
  begin
    Exit;
  end;
  if not ATokens[mFirst].IsKeyword('unit') then
  begin
    // program, library, package: ein uses (bzw. contains) hinter dem Kopf.
    Exit(mHeaderEnd);
  end;
  mInterface_ := NextCodeAfter(ATokens, mHeaderEnd);
  if (mInterface_ > High(ATokens)) or not ATokens[mInterface_].IsKeyword('interface') then
  begin
    Exit;
  end;
  mImplementation_ := -1;
  for mIndex := mInterface_ + 1 to High(ATokens) do
  begin
    if ATokens[mIndex].IsKeyword('implementation') then
    begin
      mImplementation_ := mIndex;
      Break;
    end;
  end;
  if (mImplementation_ >= 0) and (AOffset >= ATokens[mImplementation_].Offset) then
  begin
    Result := mImplementation_;
  end
  else
  begin
    Result := mInterface_;
  end;
end;

class function TPascalUses.ReadNames(const ATokens: TArray<TPascalToken>; AUses: Integer;
  var ANames: TArray<string>): Integer;
var
  mIndex: Integer;
  mName: string;
  mAfterIn: Boolean;
begin
  // uses A, B.C in 'b.pas', D; liefert den Index des Semikolons.
  mIndex := AUses + 1;
  mName := '';
  mAfterIn := False;
  while mIndex <= High(ATokens) do
  begin
    if ATokens[mIndex].IsSymbol(';') or ATokens[mIndex].IsSymbol(',') then
    begin
      if mName <> '' then
      begin
        ANames := ANames + [mName];
      end;
      mName := '';
      mAfterIn := False;
      if ATokens[mIndex].IsSymbol(';') then
      begin
        Exit(mIndex);
      end;
    end
    else if ATokens[mIndex].IsKeyword('in') then
    begin
      mAfterIn := True;
    end
    else if not mAfterIn and ((ATokens[mIndex].Kind = TPascalTokenKind.Identifier) or ATokens[mIndex].IsSymbol('.')) then
    begin
      mName := mName + ATokens[mIndex].Text;
    end;
    Inc(mIndex);
  end;
  Result := -1;
end;


class function TPascalUses.InClause(const ATokens: TArray<TPascalToken>;
  const AClauses: TArray<TUsesClauseInfo>; AOffset: Integer): Boolean;
var
  mClause: TUsesClauseInfo;
begin
  Result := False;
  for mClause in AClauses do
  begin
    if (AOffset > ATokens[mClause.UsesIndex].Offset) and (AOffset < ATokens[mClause.Semicolon].Offset) then
    begin
      Exit(True);
    end;
  end;
end;

class function TPascalUses.UsedUnits(const ATokens: TArray<TPascalToken>): TArray<string>;
var
  mIndex: Integer;
begin
  Result := nil;
  mIndex := 0;
  while mIndex <= High(ATokens) do
  begin
    if ATokens[mIndex].IsKeyword('uses') or ATokens[mIndex].IsKeyword('requires') then
    begin
      mIndex := ReadNames(ATokens, mIndex, Result);
      if mIndex < 0 then
      begin
        Exit;
      end;
    end;
    Inc(mIndex);
  end;
end;

class function TPascalUses.UsedUnitsOf(const AText: string): TArray<string>;
begin
  Result := UsedUnits(TPascalLexer.Tokenize(AText));
end;

class function TPascalUses.IsTestUnit(const ATokens: TArray<TPascalToken>): Boolean;
begin
  Result := UsesTestFramework(UsedUnits(ATokens));
end;

/// <summary>True am Anfang einer uses-, contains- oder requires-Liste. contains und
/// requires sind keine reservierten Wörter, nur am Anweisungsanfang gemeint.</summary>
function IsListStart(const ATokens: TArray<TPascalToken>; AIndex: Integer): Boolean;
var
  mPrevious: Integer;
begin
  if ATokens[AIndex].IsKeyword('uses') or ATokens[AIndex].IsKeyword('requires') or
    ATokens[AIndex].IsKeyword('contains') then
  begin
    Exit(True);
  end;
  if not ((ATokens[AIndex].Kind = TPascalTokenKind.Identifier) and
    (SameText(ATokens[AIndex].Text, 'contains') or SameText(ATokens[AIndex].Text, 'requires'))) then
  begin
    Exit(False);
  end;
  mPrevious := AIndex - 1;
  while (mPrevious >= 0) and IsTrivia(ATokens[mPrevious]) do
  begin
    Dec(mPrevious);
  end;
  Result := (mPrevious >= 0) and ATokens[mPrevious].IsSymbol(';');
end;

/// <summary>Token-Index von "implementation"; Length(ATokens) ohne.</summary>
function ImplementationIndex(const ATokens: TArray<TPascalToken>): Integer;
var
  mIndex: Integer;
begin
  Result := Length(ATokens);
  for mIndex := 0 to High(ATokens) do
  begin
    if ATokens[mIndex].IsKeyword('implementation') then
    begin
      Exit(mIndex);
    end;
  end;
end;

/// <summary>Art der Liste zum Schlüsselwort AToken (uses, contains, requires).</summary>
function ListKindOf(const AToken: TPascalToken): TUsesListKind;
begin
  Result := TUsesListKind.UsesList;
  if SameText(AToken.Text, 'contains') then
  begin
    Result := TUsesListKind.ContainsList;
  end
  else if SameText(AToken.Text, 'requires') then
  begin
    Result := TUsesListKind.RequiresList;
  end;
end;

type
  /// <summary>Liest die Einträge einer Liste: uses A, B.C in 'b.pas', D; ein Eintrag je Name, Position über alle
  /// Namensteile.</summary>
  TReferenceReader = record
    Name: string;
    First: Integer;
    Last: Integer;
    AfterIn: Boolean;
    /// <summary>Vorlage mit List und InInterface.</summary>
    Reference: TUsesReference;
    /// <summary>Schließt den Eintrag am Komma bzw. Semikolon ab.</summary>
    procedure Flush(const ATokens: TArray<TPascalToken>; var AResult: TArray<TUsesReference>);
    /// <summary>Nimmt das Token an AIndex auf (Namensteil oder "in").</summary>
    procedure Take(const ATokens: TArray<TPascalToken>; AIndex: Integer);
  end;

{ TReferenceReader }

procedure TReferenceReader.Flush(const ATokens: TArray<TPascalToken>; var AResult: TArray<TUsesReference>);
begin
  if Name <> '' then
  begin
    Reference.Name := Name;
    Reference.Range := TTextRange.Create(ATokens[First].StartPos, ATokens[Last].EndPos);
    AResult := AResult + [Reference];
  end;
  Name := '';
  First := -1;
  AfterIn := False;
end;

procedure TReferenceReader.Take(const ATokens: TArray<TPascalToken>; AIndex: Integer);
begin
  if ATokens[AIndex].IsKeyword('in') then
  begin
    AfterIn := True;
  end
  else if not AfterIn and ((ATokens[AIndex].Kind = TPascalTokenKind.Identifier) or
    ATokens[AIndex].IsSymbol('.')) then
  begin
    if First < 0 then
    begin
      First := AIndex;
    end;
    Last := AIndex;
    Name := Name + ATokens[AIndex].Text;
  end;
end;

/// <summary>Liest die Liste, deren Schlüsselwort an AIndex steht, nach AResult; AIndex steht danach auf dem
/// abschließenden Semikolon (bzw. hinter dem letzten Token).</summary>
procedure ReadReferences(const ATokens: TArray<TPascalToken>; var AIndex: Integer; AInInterface: Boolean;
  var AResult: TArray<TUsesReference>);
var
  mReader: TReferenceReader;
begin
  mReader := Default(TReferenceReader);
  mReader.First := -1;
  mReader.Last := -1;
  mReader.Reference.InInterface := AInInterface;
  mReader.Reference.List := ListKindOf(ATokens[AIndex]);
  Inc(AIndex);
  while AIndex <= High(ATokens) do
  begin
    if ATokens[AIndex].IsSymbol(';') or ATokens[AIndex].IsSymbol(',') then
    begin
      mReader.Flush(ATokens, AResult);
      if ATokens[AIndex].IsSymbol(';') then
      begin
        Break;
      end;
    end
    else
    begin
      mReader.Take(ATokens, AIndex);
    end;
    Inc(AIndex);
  end;
end;

class function TPascalUses.UsesTestFramework(const AUsed: TArray<string>): Boolean;
var
  mName: string;
begin
  for mName in AUsed do
  begin
    if SameText(mName, 'DUnitX.TestFramework') or SameText(mName, 'TestFramework') or
      mName.StartsWith('TestInsight.', True) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

class function TPascalUses.References(const ATokens: TArray<TPascalToken>): TArray<TUsesReference>;
var
  mIndex, mFirst, mImplementation: Integer;
  mIsUnit: Boolean;
begin
  Result := nil;
  // Abschnitt je Eintrag (#268): in einer Unit gilt alles vor "implementation" als interface.
  mFirst := FirstIndex(ATokens);
  mIsUnit := (mFirst >= 0) and ATokens[mFirst].IsKeyword('unit');
  mImplementation := ImplementationIndex(ATokens);
  mIndex := 0;
  while mIndex <= High(ATokens) do
  begin
    if IsListStart(ATokens, mIndex) then
    begin
      ReadReferences(ATokens, mIndex, mIsUnit and (mIndex < mImplementation), Result);
    end;
    Inc(mIndex);
  end;
end;

class function TPascalUses.OwnName(const ATokens: TArray<TPascalToken>): string;
var
  mFirst, mHeaderEnd, mIndex: Integer;
begin
  Result := '';
  mFirst := FirstIndex(ATokens);
  if mFirst < 0 then
  begin
    Exit;
  end;
  mHeaderEnd := SemicolonAfter(ATokens, mFirst);
  if mHeaderEnd < 0 then
  begin
    Exit;
  end;
  for mIndex := mFirst + 1 to mHeaderEnd - 1 do
  begin
    if (ATokens[mIndex].Kind = TPascalTokenKind.Identifier) or ATokens[mIndex].IsSymbol('.') then
    begin
      Result := Result + ATokens[mIndex].Text;
    end
    else if not IsTrivia(ATokens[mIndex]) then
    begin
      Break;
    end;
  end;
end;

class function TPascalUses.IsPlainList(const ATokens: TArray<TPascalToken>; AFirst, ALast: Integer): Boolean;
var
  mIndex: Integer;
begin
  for mIndex := AFirst to ALast do
  begin
    if (ATokens[mIndex].Kind = TPascalTokenKind.Directive) or
      ((ATokens[mIndex].Kind = TPascalTokenKind.Comment) and (Copy(ATokens[mIndex].Text, 1, 2) = '//')) then
    begin
      Exit(False);
    end;
  end;
  Result := True;
end;

class function TPascalUses.Clauses(const ATokens: TArray<TPascalToken>): TArray<TUsesClauseInfo>;
var
  mIndex: Integer;
  mIsUnit, mInImplementation: Boolean;
  mClause: TUsesClauseInfo;
begin
  Result := nil;
  mIndex := FirstIndex(ATokens);
  mIsUnit := (mIndex >= 0) and ATokens[mIndex].IsKeyword('unit');
  mInImplementation := False;
  mIndex := 0;
  while mIndex <= High(ATokens) do
  begin
    if ATokens[mIndex].IsKeyword('implementation') then
    begin
      mInImplementation := True;
    end
    else if ATokens[mIndex].IsKeyword('uses') then
    begin
      mClause.UsesIndex := mIndex;
      mClause.Names := nil;
      mClause.Semicolon := ReadNames(ATokens, mIndex, mClause.Names);
      if mClause.Semicolon < 0 then
      begin
        Exit;
      end;
      mClause.InInterface := mIsUnit and not mInImplementation;
      mClause.Plain := IsPlainList(ATokens, mIndex + 1, mClause.Semicolon - 1);
      Result := Result + [mClause];
      mIndex := mClause.Semicolon;
    end;
    Inc(mIndex);
  end;
end;

class function TPascalUses.IsUsed(const AUsed: TArray<string>; const AUnitName: string;
  const ANamespaces: TArray<string>): Boolean;
var
  mUsed, mNamespace: string;
begin
  for mUsed in AUsed do
  begin
    if SameText(mUsed, AUnitName) then
    begin
      Exit(True);
    end;
    for mNamespace in ANamespaces do
    begin
      if SameText(mNamespace + '.' + mUsed, AUnitName) then
      begin
        Exit(True);
      end;
    end;
  end;
  Result := False;
end;


class function TPascalUses.ActiveTokens(const ATokens: TArray<TPascalToken>;
  const AInactive: TArray<TTextRange>): TArray<TPascalToken>;
var
  mCount, mIndex: Integer;
begin
  if AInactive = nil then
  begin
    Exit(ATokens);
  end;
  SetLength(Result, Length(ATokens));
  mCount := 0;
  for mIndex := 0 to High(ATokens) do
  begin
    if not TTextRange.AnyContains(AInactive, ATokens[mIndex].StartPos) then
    begin
      Result[mCount] := ATokens[mIndex];
      Inc(mCount);
    end;
  end;
  SetLength(Result, mCount);
end;

end.
