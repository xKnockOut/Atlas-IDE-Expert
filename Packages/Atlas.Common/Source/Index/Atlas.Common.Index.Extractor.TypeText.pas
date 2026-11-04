unit Atlas.Common.Index.Extractor.TypeText;

// Typen, Typparameter, Parameterlisten, uses-Listen und Namenszählung aus dem Syntaxbaum für den
// Symbolindex. Ausgelagert aus Atlas.Common.Index.Extractor; liest nur den Baum, keine Tokens.

interface

uses
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Index.Contract;

type
  TIndexTypeText = class
  public
    /// <summary>Kopf einer Routine mit Rumpf (RoutineDecl), sonst ANode selbst.</summary>
    class function HeaderOf(ANode: TSyntaxNode): TSyntaxNode; static;
    /// <summary>Knoten des ersten direkten Typverweises (A: TFoo, function F: TFoo); sonst nil.</summary>
    class function DeclaredTypeNode(ANode: TSyntaxNode): TSyntaxNode; static;
    /// <summary>Name des ersten direkten Typverweises; sonst ''.</summary>
    class function DeclaredType(ANode: TSyntaxNode): string; static;
    /// <summary>Typargumente eines Typverweises kommagetrennt ('' ohne).</summary>
    class function GenericArgsText(ATypeRef: TSyntaxNode): string; static;
    /// <summary>Typ als Text samt Typargumenten: TDictionary&lt;string, TList&lt;TKunde&gt;&gt; (#263).</summary>
    class function TypeText(ANode: TSyntaxNode): string; static;
    /// <summary>Typparameter aus GenericParams eines Knotens kommagetrennt ('' ohne).</summary>
    class function TypeParamsOf(ANode: TSyntaxNode): string; static;
    /// <summary>Parameterzahlen und -typen eines Routinenkopfs oder einer indizierten Property.</summary>
    class procedure ParamInfo(ANode: TSyntaxNode; out AMin, AMax: Integer; out ATypes: TArray<string>); static;
    /// <summary>Methodenkopf mit virtual, dynamic, abstract oder override?</summary>
    class function IsVirtualHeader(ANode: TSyntaxNode): Boolean; static;
    /// <summary>Prozedurtyp, den die Typdeklaration ANode deklariert (TEreignis = procedure … of object); nil bei
    /// anderen Typen.</summary>
    class function ProcedureTypeOf(ANode: TSyntaxNode): TSyntaxNode; static;
    /// <summary>Units der uses-Klausel des Abschnitts ASection (nil ohne).</summary>
    class function UsesOf(ASection: TSyntaxNode): TArray<string>; static;
    /// <summary>Beginnt AName mit APrefix vor einem Großbuchstaben (FName, AValue, LIndex)?</summary>
    class function HasNamePrefix(const AName, APrefix: string): Boolean; static;
    /// <summary>Felder (auch in Records und var-Abschnitten von Klassen), Parameter und lokale Variablen
    /// (var-Abschnitte von Routinen und Inline-Variablen) unter ARoot, gezählt mit Präfix (#452).</summary>
    class function NamingOf(ARoot: TSyntaxNode): TNamingCounts; static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections;

class function TIndexTypeText.HeaderOf(ANode: TSyntaxNode): TSyntaxNode;
begin
  Result := ANode;
  if (ANode.Kind = TSyntaxKind.RoutineDecl) and (ANode.FindChild(TSyntaxKind.RoutineHeader) <> nil) then
  begin
    Result := ANode.FindChild(TSyntaxKind.RoutineHeader);
  end;
end;

class function TIndexTypeText.DeclaredTypeNode(ANode: TSyntaxNode): TSyntaxNode;
var
  mNode: TSyntaxNode;
  mIndex: Integer;
begin
  // Erster direkter Typverweis: A: TFoo, property P: TFoo, function F: TFoo.
  // Bei RoutineDecl steht der Typ im Kopf.
  mNode := HeaderOf(ANode);
  for mIndex := 0 to mNode.ChildCount - 1 do
  begin
    if mNode[mIndex].Kind = TSyntaxKind.TypeReference then
    begin
      Exit(mNode[mIndex]);
    end;
  end;
  Result := nil;
end;

class function TIndexTypeText.DeclaredType(ANode: TSyntaxNode): string;
var
  mNode: TSyntaxNode;
begin
  mNode := DeclaredTypeNode(ANode);
  if mNode <> nil then
  begin
    Result := mNode.Name;
  end
  else
  begin
    Result := '';
  end;
end;

class function TIndexTypeText.GenericArgsText(ATypeRef: TSyntaxNode): string;
var
  mArgs: TSyntaxNode;
  mIndex: Integer;
begin
  Result := '';
  if ATypeRef = nil then
  begin
    Exit;
  end;
  mArgs := ATypeRef.FindChild(TSyntaxKind.GenericArgs);
  if mArgs = nil then
  begin
    Exit;
  end;
  for mIndex := 0 to mArgs.ChildCount - 1 do
  begin
    if Result <> '' then
    begin
      Result := Result + ',';
    end;
    Result := Result + TypeText(mArgs[mIndex]);
  end;
end;

class function TIndexTypeText.TypeText(ANode: TSyntaxNode): string;
var
  mArgs: string;
begin
  Result := '';
  if ANode = nil then
  begin
    Exit;
  end;
  case ANode.Kind of
    TSyntaxKind.TypeReference:
      begin
        Result := ANode.Name;
        mArgs := GenericArgsText(ANode);
        if mArgs <> '' then
        begin
          Result := Result + '<' + mArgs + '>';
        end;
      end;
    TSyntaxKind.ArrayType:
      if ANode.FindChild(TSyntaxKind.TypeReference) <> nil then
      begin
        Result := 'array of ' + TypeText(ANode[ANode.ChildCount - 1]);
      end;
  else
    // Übrige Werte bewusst ohne Wirkung.
  end;
end;

class function TIndexTypeText.TypeParamsOf(ANode: TSyntaxNode): string;
var
  mParams: TSyntaxNode;
  mIndex: Integer;
begin
  Result := '';
  mParams := HeaderOf(ANode).FindChild(TSyntaxKind.GenericParams);
  if mParams = nil then
  begin
    Exit;
  end;
  for mIndex := 0 to mParams.ChildCount - 1 do
  begin
    if mParams[mIndex].Name <> '' then
    begin
      if Result <> '' then
      begin
        Result := Result + ',';
      end;
      Result := Result + mParams[mIndex].Name;
    end;
  end;
end;

/// <summary>Typknoten eines Parameters (nil bei untypisierten); AHasDefault: Es folgt ein Standardwert.</summary>
function ParamTypeOf(AParam: TSyntaxNode; out AHasDefault: Boolean): TSyntaxNode;
var
  mChild: Integer;
begin
  // Kinder: Typ (fehlt bei untypisierten Parametern), danach ggf. der Standardwert.
  Result := nil;
  AHasDefault := False;
  for mChild := 0 to AParam.ChildCount - 1 do
  begin
    if (Result = nil) and (AParam[mChild].Kind in [TSyntaxKind.TypeReference, TSyntaxKind.ArrayType]) then
    begin
      Result := AParam[mChild];
    end
    else
    begin
      AHasDefault := True;
    end;
  end;
end;

class procedure TIndexTypeText.ParamInfo(ANode: TSyntaxNode; out AMin, AMax: Integer; out ATypes: TArray<string>);
var
  mParams, mParam: TSyntaxNode;
  mIndex, mCount: Integer;
  mParamType: string;
  mHasDefault: Boolean;
begin
  AMin := 0;
  AMax := 0;
  ATypes := nil;
  mParams := HeaderOf(ANode).FindChild(TSyntaxKind.Parameters);
  if mParams = nil then
  begin
    Exit;
  end;
  for mIndex := 0 to mParams.ChildCount - 1 do
  begin
    mParam := mParams[mIndex];
    if mParam.Kind <> TSyntaxKind.Parameter then
    begin
      Continue;
    end;
    mParamType := TypeText(ParamTypeOf(mParam, mHasDefault));
    // A, B: Integer zählt zweimal.
    for mCount := 1 to Length(mParam.Name.Split([','])) do
    begin
      Inc(AMax);
      if not mHasDefault then
      begin
        Inc(AMin);
      end;
      ATypes := ATypes + [mParamType];
    end;
  end;
end;

class function TIndexTypeText.IsVirtualHeader(ANode: TSyntaxNode): Boolean;
var
  mIndex: Integer;
begin
  Result := False;
  if ANode.Kind <> TSyntaxKind.RoutineHeader then
  begin
    Exit;
  end;
  for mIndex := 0 to ANode.ChildCount - 1 do
  begin
    if (ANode[mIndex].Kind = TSyntaxKind.Directive) and
      MatchText(ANode[mIndex].Name, ['virtual', 'dynamic', 'abstract', 'override']) then
    begin
      Exit(True);
    end;
  end;
end;

class function TIndexTypeText.ProcedureTypeOf(ANode: TSyntaxNode): TSyntaxNode;
var
  mIndex: Integer;
begin
  Result := nil;
  if (ANode = nil) or (ANode.Kind <> TSyntaxKind.TypeDecl) then
  begin
    Exit;
  end;
  // Rumpf ist das erste Kind außer Typparametern und Attributen (wie in AddType).
  for mIndex := 0 to ANode.ChildCount - 1 do
  begin
    if not (ANode[mIndex].Kind in [TSyntaxKind.GenericParams, TSyntaxKind.Attribute]) then
    begin
      if ANode[mIndex].Kind = TSyntaxKind.ProcedureType then
      begin
        Result := ANode[mIndex];
      end;
      Exit;
    end;
  end;
end;

class function TIndexTypeText.UsesOf(ASection: TSyntaxNode): TArray<string>;
var
  mClause: TSyntaxNode;
  mNames: TList<string>;
  mIndex: Integer;
begin
  Result := nil;
  if ASection = nil then
  begin
    Exit;
  end;
  mClause := ASection.FindChild(TSyntaxKind.UsesClause);
  if mClause = nil then
  begin
    Exit;
  end;
  mNames := TList<string>.Create;
  try
    for mIndex := 0 to mClause.ChildCount - 1 do
    begin
      if (mClause[mIndex].Kind = TSyntaxKind.UsedUnit) and (mClause[mIndex].Name <> '') then
      begin
        mNames.Add(mClause[mIndex].Name);
      end;
    end;
    Result := mNames.ToArray;
  finally
    mNames.Free;
  end;
end;

class function TIndexTypeText.HasNamePrefix(const AName, APrefix: string): Boolean;
begin
  Result := (APrefix <> '') and (Length(AName) > Length(APrefix)) and StartsStr(APrefix, AName) and
    CharInSet(AName[Length(APrefix) + 1], ['A'..'Z']);
end;

/// <summary>Art der Namen in einer var-Deklaration: Typ = Feld, Routine = lokal; False für globale Variablen.
/// </summary>
function VarNamingKindOf(ANode: TSyntaxNode; out AKind: TNamingKind): Boolean;
var
  mOwner: TSyntaxNode;
begin
  // Nächster Besitzer entscheidet: Typ = Feld, Routine = lokal, sonst global.
  mOwner := ANode.Parent;
  while (mOwner <> nil) and not (mOwner.Kind in [TSyntaxKind.ClassType, TSyntaxKind.ObjectType,
    TSyntaxKind.RecordType, TSyntaxKind.HelperType, TSyntaxKind.RoutineDecl]) do
  begin
    mOwner := mOwner.Parent;
  end;
  Result := mOwner <> nil;
  if not Result then
  begin
    AKind := TNamingKind.Local;
  end
  else if mOwner.Kind = TSyntaxKind.RoutineDecl then
  begin
    AKind := TNamingKind.Local;
  end
  else
  begin
    AKind := TNamingKind.Field;
  end;
end;

/// <summary>Art der Namen in ANode (Field, VarDecl, Parameter, InlineVar); False für globale Variablen,
/// Konstanten und alles andere.</summary>
function NamingKindOf(ANode: TSyntaxNode; out AKind: TNamingKind): Boolean;
begin
  Result := True;
  AKind := TNamingKind.Local;
  case ANode.Kind of
    TSyntaxKind.Field:
      AKind := TNamingKind.Field;
    TSyntaxKind.Parameter:
      AKind := TNamingKind.Parameter;
    TSyntaxKind.InlineVar:
      AKind := TNamingKind.Local;
    TSyntaxKind.VarDecl:
      Result := VarNamingKindOf(ANode, AKind);
  else
    Result := False;
  end;
end;

/// <summary>Zählt die Namen in ANode ("A, B") unter ihrer Art in ACounts.</summary>
procedure CountNames(ANode: TSyntaxNode; var ACounts: TNamingCounts);
var
  mKind: TNamingKind;
  mName: string;
begin
  if not NamingKindOf(ANode, mKind) then
  begin
    Exit;
  end;
  for mName in ANode.Name.Split([',']) do
  begin
    if Trim(mName) <> '' then
    begin
      Inc(ACounts[mKind].Total);
      if TIndexTypeText.HasNamePrefix(Trim(mName), NamingPrefixes[mKind]) then
      begin
        Inc(ACounts[mKind].Prefixed);
      end;
    end;
  end;
end;

class function TIndexTypeText.NamingOf(ARoot: TSyntaxNode): TNamingCounts;
var
  mCounts: TNamingCounts;
begin
  mCounts := Default(TNamingCounts);
  if ARoot <> nil then
  begin
    ARoot.Walk(
      function(ANode: TSyntaxNode): Boolean
      begin
        Result := True;
        CountNames(ANode, mCounts);
      end);
  end;
  Result := mCounts;
end;

end.
