unit Argus.Common.Pascal.LanguageFeatures;

// Sprachmerkmale mit der Delphi-Version (BDS-Versionsnummer), ab der sie
// verfügbar sind. Check findet im Syntaxbaum Merkmale, die die eingestellte
// Version noch nicht kennt. Ohne gültige Version wird nichts gemeldet.

interface

{$SCOPEDENUMS ON}

uses
  System.SysUtils,
  Argus.Common.Documents.Contract,
  Argus.Common.Pascal.SyntaxTree;

type
  TLanguageFeature = (InlineVariable, InlineConstant, ManagedRecord, MultilineString, IfExpression);

  TLanguageFeatureFinding = record
    Feature: TLanguageFeature;
    StartPos: TTextPosition;
    EndPos: TTextPosition;
    Message: string;
  end;

  TLanguageFeatures = class
  public
    /// <summary>Mindestversion als BDS-Nummer, z. B. 20.0 für Delphi 10.3.</summary>
    class function MinimumVersion(AFeature: TLanguageFeature): string; static;
    class function DisplayName(AFeature: TLanguageFeature): string; static;
    /// <summary>Wandelt "37.0" oder "37" in 37000 um; -1 bei ungültiger Angabe.</summary>
    class function ParseVersion(const AVersion: string): Integer; static;
    class function IsAvailable(AFeature: TLanguageFeature; const AVersion: string): Boolean; static;
    /// <summary>Merkmale im Baum, die AVersion nicht kennt.</summary>
    class function Check(ATree: TSyntaxTree; const AVersion: string): TArray<TLanguageFeatureFinding>; static;
  end;

implementation

uses
  System.Generics.Collections,
  Argus.Common.Pascal.Contract;

const
  Minimums: array[TLanguageFeature] of string = ('20.0', '20.0', '21.0', '23.0', '37.0');
  Names: array[TLanguageFeature] of string = ('Inline-Variable', 'Inline-Konstante',
    'Managed Record (class operator Initialize/Finalize)', 'Mehrzeiliger String', 'If-Ausdruck');

class function TLanguageFeatures.MinimumVersion(AFeature: TLanguageFeature): string;
begin
  Result := Minimums[AFeature];
end;

class function TLanguageFeatures.DisplayName(AFeature: TLanguageFeature): string;
begin
  Result := Names[AFeature];
end;

class function TLanguageFeatures.ParseVersion(const AVersion: string): Integer;
var
  Text, MajorText, MinorText: string;
  Dot, Major, Minor: Integer;
begin
  Text := Trim(AVersion);
  Dot := Pos('.', Text);
  if Dot > 0 then
  begin
    MajorText := Copy(Text, 1, Dot - 1);
    MinorText := Copy(Text, Dot + 1, MaxInt);
  end
  else
  begin
    MajorText := Text;
    MinorText := '0';
  end;
  if not TryStrToInt(MajorText, Major) or not TryStrToInt(MinorText, Minor) or
    (Major < 0) or (Minor < 0) or (Minor > 999) then
    Exit(-1);
  Result := Major * 1000 + Minor;
end;

class function TLanguageFeatures.IsAvailable(AFeature: TLanguageFeature; const AVersion: string): Boolean;
var
  Version: Integer;
begin
  Version := ParseVersion(AVersion);
  Result := (Version < 0) or (Version >= ParseVersion(Minimums[AFeature]));
end;

procedure AddFinding(AList: TList<TLanguageFeatureFinding>; AFeature: TLanguageFeature;
  const AStartPos, AEndPos: TTextPosition; const AVersion: string);
var
  Finding: TLanguageFeatureFinding;
begin
  Finding.Feature := AFeature;
  Finding.StartPos := AStartPos;
  Finding.EndPos := AEndPos;
  Finding.Message := Format('%s erst ab Delphi-Version %s verfügbar (eingestellt: %s)',
    [Names[AFeature], Minimums[AFeature], AVersion]);
  AList.Add(Finding);
end;

procedure WalkNodes(ANode: TSyntaxNode; AList: TList<TLanguageFeatureFinding>; const AVersion: string);
var
  Index: Integer;
  Feature: TLanguageFeature;
  Found: Boolean;
begin
  Found := True;
  Feature := TLanguageFeature.InlineVariable;
  case ANode.Kind of
    TSyntaxKind.InlineVar:
      Feature := TLanguageFeature.InlineVariable;
    TSyntaxKind.InlineConst:
      Feature := TLanguageFeature.InlineConstant;
    TSyntaxKind.IfExpr:
      Feature := TLanguageFeature.IfExpression;
  else
    Found := False;
  end;
  if Found and not TLanguageFeatures.IsAvailable(Feature, AVersion) then
    AddFinding(AList, Feature, ANode.StartPos, ANode.EndPos, AVersion);
  for Index := 0 to ANode.ChildCount - 1 do
    WalkNodes(ANode.Children[Index], AList, AVersion);
end;

procedure WalkTokens(const ATokens: TArray<TPascalToken>; AList: TList<TLanguageFeatureFinding>;
  const AVersion: string);
var
  Index: Integer;
begin
  for Index := 0 to High(ATokens) do
  begin
    if (ATokens[Index].Kind = TPascalTokenKind.StringLiteral) and
      (Copy(ATokens[Index].Text, 1, 3) = '''''''') and
      (ATokens[Index].StartPos.Line <> ATokens[Index].EndPos.Line) and
      not TLanguageFeatures.IsAvailable(TLanguageFeature.MultilineString, AVersion) then
      AddFinding(AList, TLanguageFeature.MultilineString, ATokens[Index].StartPos,
        ATokens[Index].EndPos, AVersion);
    if (Index + 2 <= High(ATokens)) and ATokens[Index].IsKeyword('class') and
      SameText(ATokens[Index + 1].Text, 'operator') and
      (SameText(ATokens[Index + 2].Text, 'Initialize') or SameText(ATokens[Index + 2].Text, 'Finalize')) and
      not TLanguageFeatures.IsAvailable(TLanguageFeature.ManagedRecord, AVersion) then
      AddFinding(AList, TLanguageFeature.ManagedRecord, ATokens[Index].StartPos,
        ATokens[Index + 2].EndPos, AVersion);
  end;
end;

class function TLanguageFeatures.Check(ATree: TSyntaxTree; const AVersion: string): TArray<TLanguageFeatureFinding>;
var
  List: TList<TLanguageFeatureFinding>;
begin
  if ParseVersion(AVersion) < 0 then
    Exit(nil);
  List := TList<TLanguageFeatureFinding>.Create;
  try
    WalkNodes(ATree.Root, List, AVersion);
    WalkTokens(ATree.Tokens, List, AVersion);
    Result := List.ToArray;
  finally
    List.Free;
  end;
end;

end.
