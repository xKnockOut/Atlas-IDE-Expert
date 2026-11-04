unit Atlas.IDE.Search.Counter;

// Atlas-Suche im Editor (#877, #893): Zähler „n von m“ bzw. „n Treffer in m Dateien“ und die Vorschau der
// Ersetzung (nur mit Regex und offener Ersetzen-Zeile) in der offenen Leiste. Nur im Hauptthread.

interface

type
  TAtlasIdeSearchCounter = class
  public
    /// <summary>Zähler und Vorschau der offenen Leiste nach der letzten Suche.</summary>
    class procedure Update; static;
    /// <summary>Vorschau des Treffers an der Schreibmarke; ohne Regex ist der neue Text das Feld selbst.</summary>
    class procedure Preview; static;
  end;

implementation

uses
  ToolsAPI,
  Atlas.Core.Search.Matching,
  Atlas.Core.Search.Replace,
  Atlas.Core.Search.Results,
  Atlas.UI.Search.Strings,
  Atlas.IDE.Search.Editor,
  Atlas.IDE.Search.Session;

/// <summary>„3 von 12“, ohne Treffer an der Schreibmarke „12 Treffer“, ohne Treffer „keine Treffer“.</summary>
function PositionText(const AHits: TArray<TAtlasSearchHit>; const AAt: TAtlasSearchPos): string;
var
  mIndex: Integer;
begin
  if Length(AHits) = 0 then
  begin
    Exit(TAtlasSearchStrings.Text(TAtlasSearchTextId.SearchNoHits));
  end;
  mIndex := TAtlasSearchResults.IndexAt(AHits, AAt);
  if mIndex >= 0 then
  begin
    Result := TAtlasSearchStrings.Fmt(TAtlasSearchTextId.SearchHitPosition, [mIndex + 1, Length(AHits)]);
  end
  else
  begin
    Result := TAtlasSearchStrings.Fmt(TAtlasSearchTextId.SearchHitCount, [Length(AHits)]);
  end;
end;

class procedure TAtlasIdeSearchCounter.Update;
var
  mView: IOTAEditView;
  mLines: TArray<string>;
  mAt: TAtlasSearchPos;
  mHits: TArray<TAtlasSearchHit>;
begin
  if not TAtlasIdeSearchSession.BarOpen or not TAtlasIdeSearchEditor.TopView(mView) then
  begin
    Exit;
  end;
  if TAtlasIdeSearchSession.Last.Text = '' then
  begin
    TAtlasIdeSearchSession.Bar.SetCounter('');
    TAtlasIdeSearchSession.Bar.ClearPreview;
    Exit;
  end;
  Preview;
  // Über Dateien (#893): Treffer und Dateien der Suche im Hintergrund.
  if TAtlasIdeSearchSession.FilesCurrent then
  begin
    if TAtlasIdeSearchSession.Files.Done then
    begin
      TAtlasIdeSearchSession.Bar.SetCounter(TAtlasIdeSearchSession.FilesCounter(
        TAtlasSearchTextId.SearchFilesCounter));
    end
    else
    begin
      TAtlasIdeSearchSession.Bar.SetCounter(TAtlasIdeSearchSession.FilesCounter(
        TAtlasSearchTextId.SearchFilesRunning));
    end;
  end
  else
  begin
    mHits := TAtlasIdeSearchEditor.HitsAtCursor(mView, TAtlasIdeSearchSession.Last, mLines, mAt);
    TAtlasIdeSearchSession.Bar.SetCounter(PositionText(mHits, mAt));
  end;
end;

class procedure TAtlasIdeSearchCounter.Preview;
var
  mView: IOTAEditView;
  mLines: TArray<string>;
  mHits: TArray<TAtlasSearchHit>;
  mAt: TAtlasSearchPos;
  mIndex: Integer;
  mPreview: TAtlasReplacePreview;
  mQuery: TAtlasSearchQuery;
begin
  if TAtlasIdeSearchSession.Bar = nil then
  begin
    Exit;
  end;
  mQuery := TAtlasIdeSearchSession.Last;
  mIndex := -1;
  // Vorschau nur mit Regex und offener Ersetzen-Zeile; ohne Regex ist der neue Text das Feld selbst.
  if TAtlasIdeSearchSession.Bar.ReplaceShown and mQuery.Options.Regex and not TAtlasIdeSearchSession.Bar.HasError and
    (mQuery.Text <> '') and TAtlasIdeSearchEditor.TopView(mView) then
  begin
    mHits := TAtlasIdeSearchEditor.HitsAtCursor(mView, mQuery, mLines, mAt);
    mIndex := TAtlasSearchResults.IndexAt(mHits, mAt);
  end;
  if mIndex < 0 then
  begin
    TAtlasIdeSearchSession.Bar.ClearPreview;
    Exit;
  end;
  mPreview := TAtlasSearchReplace.Preview(mLines, mHits[mIndex], mQuery, TAtlasIdeSearchSession.ReplaceText);
  TAtlasIdeSearchSession.Bar.SetPreview(mPreview.Before, mPreview.After);
end;

end.
