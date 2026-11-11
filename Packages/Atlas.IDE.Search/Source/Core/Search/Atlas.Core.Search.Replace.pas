unit Atlas.Core.Search.Replace;

// Ersetzen in der Atlas-Suche (#893), ohne VCL und Open Tools API:
// - Replacement: neuer Text für einen Treffer. Im Textmodus der Ersatztext
//   wie eingegeben; mit Regex gelten $0 (ganzer Treffer), $1 … $9, ${name}
//   und ${12} für Gruppen sowie $$ für ein Dollarzeichen. Eine Gruppe, die es
//   nicht gibt oder die nicht passte, ergibt nichts; ein anderes $ bleibt.
// - Preview: alter und neuer Text des Treffers für die Vorschau in der Leiste
//   und in der Liste über Dateien („vorher → nachher“).
// - Edits: Textänderungen (LSP, 0-basiert in UTF-16) für alle Treffer einer
//   Datei. Die IDE-Schicht wendet sie über TAtlasIdeWorkspaceEdit an: eine
//   Datei = ein Rückgängig-Schritt, mehrere Dateien = ein Satz im
//   mehrdateiigen Rückgängig (#721). Zeilenenden bleiben, weil nur innerhalb
//   der Zeilen ersetzt wird.
// Die Treffer kommen aus TAtlasTextSearch.FindAll mit derselben Suche; für
// Regex wird der Ausdruck auf der Zeile erneut ausgewertet, um die Gruppen zu
// bekommen.

interface

uses
  System.SysUtils,
  System.RegularExpressions,
  Atlas.Core.Lsp.WorkspaceEdits,
  Atlas.Core.Search.Matching;

type
  TAtlasReplacePreview = record
    /// <summary>Text des Treffers.</summary>
    Before: string;
    /// <summary>Text nach dem Ersetzen.</summary>
    After: string;
    /// <summary>„vorher → nachher“.</summary>
    function Caption: string;
  end;

  TAtlasSearchReplace = class
  public
    /// <summary>Ersatztext mit Gruppen aus AMatch ($0, $1 … $9, ${name}, ${12}, $$).</summary>
    class function Expand(const ATemplate: string; const AMatch: TMatch): string; static;
    /// <summary>Neuer Text für AHit in ALines nach AQuery; AReplace wie eingegeben.</summary>
    class function Replacement(const ALines: TArray<string>; const AHit: TAtlasSearchHit;
      const AQuery: TAtlasSearchQuery; const AReplace: string): string; static;
    class function Preview(const ALines: TArray<string>; const AHit: TAtlasSearchHit;
      const AQuery: TAtlasSearchQuery; const AReplace: string): TAtlasReplacePreview; static;
    /// <summary>Textänderungen für AHits (aus FindAll mit AQuery), in Textreihenfolge.</summary>
    class function Edits(const ALines: TArray<string>; const AHits: TArray<TAtlasSearchHit>;
      const AQuery: TAtlasSearchQuery; const AReplace: string): TArray<TLspTextEdit>; static;
    /// <summary>Text des Treffers in seiner Zeile; '' außerhalb.</summary>
    class function HitText(const ALines: TArray<string>; const AHit: TAtlasSearchHit): string; static;
  end;

implementation

{ TAtlasReplacePreview }

function TAtlasReplacePreview.Caption: string;
begin
  Result := Before + ' → ' + After;
end;

{ TAtlasSearchReplace }

/// <summary>Zeile ohne #13 am Ende.</summary>
function CleanLine(const ALine: string): string;
begin
  Result := ALine;
  if (Result <> '') and (Result[Length(Result)] = #13) then
  begin
    SetLength(Result, Length(Result) - 1);
  end;
end;

/// <summary>Wert der Gruppe (Nummer oder Name); '' wenn es sie nicht gibt oder sie nicht passte.</summary>
function GroupValue(const AMatch: TMatch; const AName: string): string;
var
  mNumber: Integer;
  mGroup: TGroup;
begin
  Result := '';
  try
    if TryStrToInt(AName, mNumber) then
    begin
      if (mNumber < 0) or (mNumber >= AMatch.Groups.Count) then
      begin
        Exit;
      end;
      mGroup := AMatch.Groups[mNumber];
    end
    else
    begin
      mGroup := AMatch.Groups[AName];
    end;
    if mGroup.Success then
    begin
      Result := mGroup.Value;
    end;
  except
    // Unbekannter Name: die Engine meldet ihn als Fehler; für den Ersatztext heißt das „nichts“.
    on Exception do
      Result := '';
  end;
end;

class function TAtlasSearchReplace.Expand(const ATemplate: string; const AMatch: TMatch): string;
var
  I, mClose: Integer;
  mNext: Char;
begin
  Result := '';
  I := 1;
  while I <= Length(ATemplate) do
  begin
    if (ATemplate[I] <> '$') or (I = Length(ATemplate)) then
    begin
      Result := Result + ATemplate[I];
      Inc(I);
      Continue;
    end;
    mNext := ATemplate[I + 1];
    if mNext = '$' then
    begin
      Result := Result + '$';
      Inc(I, 2);
    end
    else if CharInSet(mNext, ['0'..'9']) then
    begin
      Result := Result + GroupValue(AMatch, mNext);
      Inc(I, 2);
    end
    else if mNext = '{' then
    begin
      mClose := Pos('}', ATemplate, I + 2);
      if mClose = 0 then
      begin
        Result := Result + '$';
        Inc(I);
        Continue;
      end;
      Result := Result + GroupValue(AMatch, Copy(ATemplate, I + 2, mClose - I - 2));
      I := mClose + 1;
    end
    else
    begin
      Result := Result + '$';
      Inc(I);
    end;
  end;
end;

class function TAtlasSearchReplace.HitText(const ALines: TArray<string>; const AHit: TAtlasSearchHit): string;
begin
  Result := '';
  if (AHit.Line >= 0) and (AHit.Line <= High(ALines)) then
  begin
    Result := Copy(CleanLine(ALines[AHit.Line]), AHit.Character + 1, AHit.Length);
  end;
end;

class function TAtlasSearchReplace.Replacement(const ALines: TArray<string>; const AHit: TAtlasSearchHit;
  const AQuery: TAtlasSearchQuery; const AReplace: string): string;
var
  mLine: string;
  mFound: TMatch;
begin
  Result := AReplace;
  if not AQuery.Options.Regex or (AHit.Line < 0) or (AHit.Line > High(ALines)) then
  begin
    Exit;
  end;
  mLine := CleanLine(ALines[AHit.Line]);
  // Derselbe Ausdruck auf derselben Zeile liefert den Treffer wieder, jetzt mit Gruppen.
  mFound := TRegEx.Create(AQuery.Text, TAtlasSearchRegex.Options(AQuery.Options)).Match(mLine);
  while mFound.Success do
  begin
    if (mFound.Index - 1 = AHit.Character) and (mFound.Length = AHit.Length) then
    begin
      Exit(Expand(AReplace, mFound));
    end;
    mFound := mFound.NextMatch;
  end;
end;

class function TAtlasSearchReplace.Preview(const ALines: TArray<string>; const AHit: TAtlasSearchHit;
  const AQuery: TAtlasSearchQuery; const AReplace: string): TAtlasReplacePreview;
begin
  Result.Before := HitText(ALines, AHit);
  Result.After := Replacement(ALines, AHit, AQuery, AReplace);
end;

class function TAtlasSearchReplace.Edits(const ALines: TArray<string>; const AHits: TArray<TAtlasSearchHit>;
  const AQuery: TAtlasSearchQuery; const AReplace: string): TArray<TLspTextEdit>;
var
  mIndex: Integer;
begin
  Result := nil;
  SetLength(Result, Length(AHits));
  for mIndex := 0 to High(AHits) do
  begin
    Result[mIndex].StartPos.Line := AHits[mIndex].Line;
    Result[mIndex].StartPos.Character := AHits[mIndex].Character;
    Result[mIndex].EndPos.Line := AHits[mIndex].Line;
    Result[mIndex].EndPos.Character := AHits[mIndex].Character + AHits[mIndex].Length;
    Result[mIndex].NewText := Replacement(ALines, AHits[mIndex], AQuery, AReplace);
  end;
end;

end.
