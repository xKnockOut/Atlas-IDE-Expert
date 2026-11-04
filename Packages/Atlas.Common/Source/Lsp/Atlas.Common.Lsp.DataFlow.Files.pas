unit Atlas.Common.Lsp.DataFlow.Files;

// Datenfluss (#690): Dateien eines Laufs. Liest und parst jede Datei höchstens einmal, merkt sich Zeilen und
// Test-Units und weiß, welche Dateien zum Projekt gehören.

interface

uses
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Lsp.References,
  Atlas.Common.Lsp.DataFlow.Types;

type
  TDataFlowFiles = class
  private
    FOwnTree: TSyntaxTree;
    FOwnFile: string;
    FFiles: TArray<string>;
    FReadText: TReferenceReadText;
    FProject: TDictionary<string, Boolean>;
    FTrees: TObjectDictionary<string, TSyntaxTree>;
    FTexts: TDictionary<string, string>;
    FLines: TDictionary<string, TArray<string>>;
    FTests: TDictionary<string, Boolean>;
  public
    /// <summary>ATree gehört dem Aufrufer und steht für AFileName.</summary>
    constructor Create(const ARequest: TDataFlowRequest);
    destructor Destroy; override;
    /// <summary>Geparster Baum der Datei; nil, wenn sie sich nicht lesen lässt.</summary>
    function TreeOf(const AFileName: string): TSyntaxTree;
    function TextOf(const AFileName: string): string;
    function LineText(const AFileName: string; ALine: Integer): string;
    /// <summary>Text des Knotens, einzeilig; leer ohne Knoten.</summary>
    function ExprText(const AFileName: string; ANode: TSyntaxNode): string;
    function InProject(const AFileName: string): Boolean;
    function IsTestFile(const AFileName: string): Boolean;
    function Place(const AFileName: string; const APosition: TTextPosition): TDataFlowPlace;
    /// <summary>Projektdateien der Anfrage (leer = alles zählt zum Projekt).</summary>
    property Files: TArray<string> read FFiles;
    property ReadText: TReferenceReadText read FReadText;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Text.Lines,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Editing.UsesClause,
  Atlas.Common.Lsp.DataFlow.Syntax;

constructor TDataFlowFiles.Create(const ARequest: TDataFlowRequest);
var
  mFileName: string;
begin
  inherited Create;
  FOwnTree := ARequest.Tree;
  FOwnFile := ARequest.FileName;
  FFiles := ARequest.Files;
  FReadText := ARequest.ReadText;
  FProject := TDictionary<string, Boolean>.Create;
  for mFileName in FFiles do
  begin
    FProject.AddOrSetValue(AnsiUpperCase(mFileName), True);
  end;
  FProject.AddOrSetValue(AnsiUpperCase(FOwnFile), True);
  FTrees := TObjectDictionary<string, TSyntaxTree>.Create([doOwnsValues]);
  FTexts := TDictionary<string, string>.Create;
  FLines := TDictionary<string, TArray<string>>.Create;
  FTests := TDictionary<string, Boolean>.Create;
end;

destructor TDataFlowFiles.Destroy;
begin
  FTests.Free;
  FLines.Free;
  FTexts.Free;
  FTrees.Free;
  FProject.Free;
  inherited;
end;

function TDataFlowFiles.TextOf(const AFileName: string): string;
begin
  if FTexts.TryGetValue(AnsiUpperCase(AFileName), Result) then
  begin
    Exit;
  end;
  if not (Assigned(FReadText) and FReadText(AFileName, Result)) then
  begin
    Result := '';
  end;
  FTexts.Add(AnsiUpperCase(AFileName), Result);
end;

function TDataFlowFiles.TreeOf(const AFileName: string): TSyntaxTree;
var
  mText: string;
begin
  if SameText(AFileName, FOwnFile) then
  begin
    Exit(FOwnTree);
  end;
  if FTrees.TryGetValue(AnsiUpperCase(AFileName), Result) then
  begin
    Exit;
  end;
  Result := nil;
  mText := '';
  if AFileName <> '' then
  begin
    mText := TextOf(AFileName);
  end;
  if mText <> '' then
  begin
    Result := TSyntaxTreeCache.Parse(mText);
    FTrees.Add(AnsiUpperCase(AFileName), Result);
  end;
end;

function TDataFlowFiles.LineText(const AFileName: string; ALine: Integer): string;
var
  mLines: TArray<string>;
begin
  if not FLines.TryGetValue(AnsiUpperCase(AFileName), mLines) then
  begin
    mLines := TTextLines.SplitLines(TextOf(AFileName));
    FLines.Add(AnsiUpperCase(AFileName), mLines);
  end;
  Result := '';
  if (ALine >= 0) and (ALine < Length(mLines)) then
  begin
    Result := Trim(mLines[ALine]);
  end;
end;

function TDataFlowFiles.ExprText(const AFileName: string; ANode: TSyntaxNode): string;
begin
  Result := '';
  if ANode <> nil then
  begin
    Result := TDataFlowSyntax.SingleLine(Copy(TextOf(AFileName), ANode.StartOffset + 1,
      ANode.EndOffset - ANode.StartOffset));
  end;
end;

function TDataFlowFiles.InProject(const AFileName: string): Boolean;
begin
  // Ohne Projekt zählt jede lesbare Datei dazu.
  Result := FProject.ContainsKey(AnsiUpperCase(AFileName)) or ((Length(FFiles) = 0) and (TextOf(AFileName) <> ''));
end;

function TDataFlowFiles.IsTestFile(const AFileName: string): Boolean;
var
  mTree: TSyntaxTree;
begin
  if FTests.TryGetValue(AnsiUpperCase(AFileName), Result) then
  begin
    Exit;
  end;
  mTree := TreeOf(AFileName);
  Result := (mTree <> nil) and TUsesClauses.IsTestUnit(mTree.Tokens);
  FTests.Add(AnsiUpperCase(AFileName), Result);
end;

function TDataFlowFiles.Place(const AFileName: string; const APosition: TTextPosition): TDataFlowPlace;
begin
  Result.FileName := AFileName;
  Result.Position := APosition;
  Result.LineText := LineText(AFileName, APosition.Line);
end;

end.
