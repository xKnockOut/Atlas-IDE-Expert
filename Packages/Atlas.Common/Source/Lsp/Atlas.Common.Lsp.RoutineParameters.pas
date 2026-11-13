unit Atlas.Common.Lsp.RoutineParameters;

// Befehl atlas.server.routineParameters (#843): Name und Parameter der Routine, in deren Rumpf eine Zeile liegt.
// Das Fenster „Aufrufstapel“ des Plugins zerlegt damit die Werte im Rahmentext der IDE
// („Unit1.TForm1.Import(5,'abc',$2A3F2C0)“) in benannte Parameter mit Typ.
// Argumente: [uri, line] (Zeile ab 0).
// Antwort: {"format": 1, "routine": "TForm1.Import", "parameters": [{"name": "Anzahl", "type": "Integer",
//   "modifier": "const"}, …]}
// routine ist '' und parameters leer, wenn die Zeile in keiner Routine liegt oder in einer anonymen Methode (deren
// Rahmen nennt die IDE anders). Die innerste Routine gilt (lokale Routinen). modifier ist '', const, var, out oder
// constref; type ist '' ohne Typangabe (untypisierter var-Parameter). Kurzform der Implementierung ohne
// Parameterliste liefert keine Parameter: Das Plugin zeigt dann die Werte der IDE ohne Namen.

interface

uses
  System.JSON,
  Atlas.Common.Pascal.SyntaxTree;

type
  TLspRoutineParameter = record
    Name: string;
    TypeName: string;
    /// <summary>'', const, var, out oder constref.</summary>
    Modifier: string;
  end;

  TLspRoutineParameterList = TArray<TLspRoutineParameter>;

  TLspRoutineParameters = class
  public const
    cCommand = 'atlas.server.routineParameters';
    cMaxType = 80;
  private
    FTree: TSyntaxTree;
    FText: string;
    function TextOf(ANode: TSyntaxNode): string;
    function RoutineAt(ALine: Integer): TSyntaxNode;
    function ReadParameters(AHeader: TSyntaxNode): TLspRoutineParameterList;
  public
    constructor Create(ATree: TSyntaxTree; const AText: string);
    /// <summary>Routine und Parameter an der Zeile ALine (ab 0); False ohne Routine.</summary>
    function Answer(ALine: Integer; out ARoutine: string; out AParameters: TLspRoutineParameterList): Boolean;
    /// <summary>Der Befehl: Antwort als JSON (format 1).</summary>
    function Execute(ALine: Integer): TJSONObject;
    class function ToJson(const ARoutine: string; const AParameters: TLspRoutineParameterList): TJSONObject;
      static;
    class function ModifierText(AModifier: TParameterModifier): string; static;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections;

function Contains(ANode: TSyntaxNode; ALine: Integer): Boolean;
begin
  Result := (ANode.StartPos.Line <= ALine) and (ALine <= ANode.EndPos.Line);
end;

{ TLspRoutineParameters }

constructor TLspRoutineParameters.Create(ATree: TSyntaxTree; const AText: string);
begin
  inherited Create;
  FTree := ATree;
  FText := AText;
end;

function TLspRoutineParameters.TextOf(ANode: TSyntaxNode): string;
begin
  Result := '';
  if (ANode = nil) or (ANode.EndOffset <= ANode.StartOffset) or (ANode.EndOffset > Length(FText)) then
  begin
    Exit;
  end;
  Result := Copy(FText, ANode.StartOffset + 1, ANode.EndOffset - ANode.StartOffset);
  Result := Result.Replace(#13#10, ' ').Replace(#10, ' ').Replace(#13, ' ');
  while Pos('  ', Result) > 0 do
  begin
    Result := Result.Replace('  ', ' ');
  end;
  Result := Trim(Result);
  if Length(Result) > cMaxType then
  begin
    Result := Copy(Result, 1, cMaxType - 1) + '…';
  end;
end;

class function TLspRoutineParameters.ModifierText(AModifier: TParameterModifier): string;
const
  cTexts: array[TParameterModifier] of string = ('', 'const', 'var', 'out', 'constref');
begin
  Result := cTexts[AModifier];
end;

function TLspRoutineParameters.RoutineAt(ALine: Integer): TSyntaxNode;
var
  mNode, mNext: TSyntaxNode;
  mIndex: Integer;
begin
  // Den Baum entlang der Zeile hinab; die zuletzt passierte Routine ist die innerste. Eine anonyme Methode darunter
  // ist ein eigener Rahmen.
  Result := nil;
  if FTree = nil then
  begin
    Exit;
  end;
  mNode := FTree.Root;
  while mNode <> nil do
  begin
    if mNode.Kind = TSyntaxKind.RoutineDecl then
    begin
      Result := mNode;
    end
    else if mNode.Kind = TSyntaxKind.AnonymousMethod then
    begin
      Exit(nil);
    end;
    mNext := nil;
    for mIndex := mNode.ChildCount - 1 downto 0 do
    begin
      if Contains(mNode.Children[mIndex], ALine) then
      begin
        mNext := mNode.Children[mIndex];
        Break;
      end;
    end;
    mNode := mNext;
  end;
end;

function TLspRoutineParameters.ReadParameters(AHeader: TSyntaxNode): TLspRoutineParameterList;
var
  mParameters, mParameter, mType: TSyntaxNode;
  mIndex: Integer;
  mName: string;
  mItem: TLspRoutineParameter;
begin
  Result := nil;
  mParameters := AHeader.FindChild(TSyntaxKind.Parameters);
  if mParameters = nil then
  begin
    Exit;
  end;
  for mIndex := 0 to mParameters.ChildCount - 1 do
  begin
    mParameter := mParameters[mIndex];
    if mParameter.Kind <> TSyntaxKind.Parameter then
    begin
      Continue;
    end;
    mType := mParameter.FindChild(TSyntaxKind.TypeReference);
    if mType = nil then
    begin
      mType := mParameter.FindChild(TSyntaxKind.ArrayType);
    end;
    for mName in mParameter.Name.Split([',']) do
    begin
      mItem := Default(TLspRoutineParameter);
      mItem.Name := Trim(mName);
      mItem.TypeName := TextOf(mType);
      mItem.Modifier := ModifierText(mParameter.Modifier);
      Result := Result + [mItem];
    end;
  end;
end;

function TLspRoutineParameters.Answer(ALine: Integer; out ARoutine: string;
  out AParameters: TLspRoutineParameterList): Boolean;
var
  mRoutine, mHeader: TSyntaxNode;
begin
  ARoutine := '';
  AParameters := nil;
  mRoutine := RoutineAt(ALine);
  Result := mRoutine <> nil;
  if not Result then
  begin
    Exit;
  end;
  ARoutine := mRoutine.Name;
  mHeader := mRoutine.FindChild(TSyntaxKind.RoutineHeader);
  if mHeader <> nil then
  begin
    AParameters := ReadParameters(mHeader);
  end;
end;

function TLspRoutineParameters.Execute(ALine: Integer): TJSONObject;
var
  mRoutine: string;
  mParameters: TLspRoutineParameterList;
begin
  Answer(ALine, mRoutine, mParameters);
  Result := ToJson(mRoutine, mParameters);
end;

class function TLspRoutineParameters.ToJson(const ARoutine: string;
  const AParameters: TLspRoutineParameterList): TJSONObject;
var
  mList: TJSONArray;
  mItem: TJSONObject;
  mParameter: TLspRoutineParameter;
begin
  Result := TJSONObject.Create;
  Result.AddPair('format', TJSONNumber.Create(1));
  Result.AddPair('routine', ARoutine);
  mList := TJSONArray.Create;
  Result.AddPair('parameters', mList);
  for mParameter in AParameters do
  begin
    mItem := TJSONObject.Create;
    mList.AddElement(mItem);
    mItem.AddPair('name', mParameter.Name);
    mItem.AddPair('type', mParameter.TypeName);
    mItem.AddPair('modifier', mParameter.Modifier);
  end;
end;

end.
