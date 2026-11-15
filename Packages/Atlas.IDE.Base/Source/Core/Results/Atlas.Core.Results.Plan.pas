unit Atlas.Core.Results.Plan;

// Befehle des Ergebnisfensters (#400), Entscheidungen ohne IDE (#1967):
// - Spot: Stelle und Bezeichner am Cursor aus dem Editortext (Cursor 1-basiert,
//   Spalte mit Tabs wie im Editor); False, wenn die Zeile fehlt.
// - Found: Was nach „Implementierungen suchen“ geschieht: nichts gefunden
//   (Meldung), genau eine (gleich hinspringen) oder eine Liste.
// - SymbolCommands: Zeilen der Symbolsuche, Kennung ist der Index.

interface

uses
  Atlas.Core.Lsp.Contract,
  Atlas.Core.Commands.Palette;

type
  TAtlasResultsSpot = record
    /// <summary>Zeile und Zeichen, 0-basiert.</summary>
    Line: Integer;
    Character: Integer;
    Name: string;
  end;

  TAtlasResultsFound = (Nothing, Jump, List);

  TAtlasResultsPlan = record
  public const
    cContainerSeparator = ' · ';
  public
    class function Spot(const AText: string; ACursorLine, ACursorColumn, ATabWidth: Integer;
      out ASpot: TAtlasResultsSpot): Boolean; static;
    class function Found(ACount: Integer): TAtlasResultsFound; static;
    class function SymbolCommands(const ASymbols: TArray<TAtlasSymbol>): TArray<TAtlasCommand>; static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Completion.Word,
  Atlas.Core.Lsp.Session.Json,
  Atlas.Core.Results.Model;

class function TAtlasResultsPlan.Spot(const AText: string; ACursorLine, ACursorColumn, ATabWidth: Integer;
  out ASpot: TAtlasResultsSpot): Boolean;
var
  mLines: TArray<string>;
  mFirst, mLast: Integer;
begin
  ASpot := Default(TAtlasResultsSpot);
  mLines := AText.Split([#13#10, #10]);
  if (ACursorLine < 1) or (ACursorLine > Length(mLines)) then
  begin
    Exit(False);
  end;
  ASpot.Line := ACursorLine - 1;
  ASpot.Character := TLspSessionJson.ColumnToIndex(mLines[ASpot.Line], ACursorColumn, ATabWidth);
  mFirst := TAtlasWord.StartBefore(mLines[ASpot.Line], ASpot.Character);
  mLast := TAtlasWord.EndAfter(mLines[ASpot.Line], ASpot.Character);
  ASpot.Name := Copy(mLines[ASpot.Line], mFirst + 1, mLast - mFirst);
  Result := True;
end;

class function TAtlasResultsPlan.Found(ACount: Integer): TAtlasResultsFound;
begin
  if ACount = 0 then
  begin
    Result := TAtlasResultsFound.Nothing;
  end
  else if ACount = 1 then
  begin
    Result := TAtlasResultsFound.Jump;
  end
  else
  begin
    Result := TAtlasResultsFound.List;
  end;
end;

class function TAtlasResultsPlan.SymbolCommands(const ASymbols: TArray<TAtlasSymbol>): TArray<TAtlasCommand>;
var
  mIndex: Integer;
  mCommand: TAtlasCommand;
begin
  Result := nil;
  for mIndex := 0 to High(ASymbols) do
  begin
    mCommand := Default(TAtlasCommand);
    mCommand.Id := IntToStr(mIndex);
    mCommand.Caption := ASymbols[mIndex].Name;
    mCommand.Path := ExtractFileName(ASymbols[mIndex].FileName);
    if ASymbols[mIndex].Container <> '' then
    begin
      mCommand.Path := ASymbols[mIndex].Container + cContainerSeparator + mCommand.Path;
    end;
    mCommand.ShortCut := TAtlasResults.SymbolBadge(ASymbols[mIndex].Kind);
    Result := Result + [mCommand];
  end;
end;

end.
