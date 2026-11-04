unit Atlas.IDE.Bookmarks.QuickPopups;

// Tooltip und Kontextmenü der Spalte der schnellen Lesezeichen (#1104), aus
// Atlas.IDE.Bookmarks.QuickColumn gelöst; die Spalte entscheidet, wann sie
// erscheinen.
// - Tooltip: Nummer, Name bzw. Methode und Sprungtaste aller Marker der
//   Zeile; auf freiem Platz der Hinweis auf den Klick (nur mit
//   bookmarks.quick.gutterClick).
// - Menü: „Nummer vergeben ›“ (belegte Nummern mit Ziel), „Namen geben …“,
//   „Lesezeichen entfernen“, „Alle Lesezeichen der Datei entfernen“,
//   „Fenster ‚Lesezeichen‘ öffnen“.
// Nur im Hauptthread.

interface

uses
  System.Types,
  System.Classes,
  Vcl.Menus,
  Atlas.Core.Bookmarks.Store,
  Atlas.UI.Popup.TitledTip;

type
  TAtlasIdeQuickTip = class
  private
    FTip: TAtlasTitledTip;
  public
    constructor Create;
    destructor Destroy; override;
    function IsShown: Boolean;
    /// <summary>Liegt APoint (Bildschirm) im gezeigten Tooltip?</summary>
    function Contains(const APoint: TPoint): Boolean;
    procedure Hide;
    /// <summary>Tooltip zu den Markern AMarks bei AAt (Bildschirm); ohne Marker der Hinweis auf den Klick, ohne
    /// bookmarks.quick.gutterClick dann nichts.</summary>
    procedure Show(const AMarks: TArray<TAtlasBookmark>; const AAt: TPoint);
    /// <summary>Text des Tooltips zu den Markern einer Zeile; AJumpKey: Grundtaste für Strg+1 (0 = keine).
    /// </summary>
    class procedure TipText(const AMarks: TArray<TAtlasBookmark>; AJumpKey: Word; out ATitle, AText: string); static;
  end;

  TAtlasIdeQuickMenu = class
  private const
    MenuName = 20;
    MenuRemove = 21;
    MenuRemoveFile = 22;
    MenuWindow = 23;
  private
    FMenu: TPopupMenu;
    FFileName: string;
    FLine: Integer;
    function AddItem(AParent: TMenuItem; const ACaption: string; ATag: Integer): TMenuItem;
    procedure MenuClick(Sender: TObject);
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>Menü zur Zeile ALine (0-basiert) von AFileName mit den Markern AMarks bei APoint (Bildschirm).
    /// </summary>
    procedure Show(const AFileName: string; ALine: Integer; const AMarks: TArray<TAtlasBookmark>;
      const APoint: TPoint);
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Bookmarks.Quick,
  Atlas.UI.Bookmarks.Strings,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Bookmarks.Service,
  Atlas.IDE.Bookmarks.QuickService;

{ TAtlasIdeQuickTip }

constructor TAtlasIdeQuickTip.Create;
begin
  inherited Create;
  FTip := TAtlasTitledTip.Create(nil);
  FTip.GuardFeature := TAtlasFeature.QuickBookmarks;
end;

destructor TAtlasIdeQuickTip.Destroy;
begin
  FTip.Free;
  inherited Destroy;
end;

function TAtlasIdeQuickTip.IsShown: Boolean;
begin
  Result := FTip.IsShown;
end;

function TAtlasIdeQuickTip.Contains(const APoint: TPoint): Boolean;
begin
  Result := FTip.IsShown and PtInRect(FTip.BoundsRect, APoint);
end;

procedure TAtlasIdeQuickTip.Hide;
begin
  if FTip.IsShown then
  begin
    FTip.HidePopup;
  end;
end;

procedure TAtlasIdeQuickTip.Show(const AMarks: TArray<TAtlasBookmark>; const AAt: TPoint);
var
  mTitle, mText: string;
  mJumpKey: Word;
begin
  mJumpKey := 0;
  if TAtlasIdeSettings.Current.QuickBookmarksNumberedKeys then
  begin
    mJumpKey := Word(TAtlasIdeSettings.Current.QuickBookmarkJumpKey);
  end;
  TipText(AMarks, mJumpKey, mTitle, mText);
  if Length(AMarks) = 0 then
  begin
    if not TAtlasIdeSettings.Current.QuickBookmarksGutterClick then
    begin
      Exit;
    end;
    mText := TAtlasBookmarksStrings.Text(TAtlasBookmarksTextId.QuickBookmarkTipFree);
  end;
  FTip.ShowNote(mTitle, mText, AAt);
end;

/// <summary>Zeile des Tooltips zu einem Marker: Nummer, Name und Sprungtaste.</summary>
function TipLine(const AMark: TAtlasBookmark; AJumpKey: Word): string;
var
  mKey: Word;
begin
  Result := AMark.DisplayName;
  if AMark.Number <= 0 then
  begin
    Exit;
  end;
  Result := IntToStr(AMark.Number) + ' · ' + Result;
  mKey := TAtlasQuickBookmarks.KeyFor(AJumpKey, AMark.Number);
  if mKey <> 0 then
  begin
    Result := Result + ' — ' + TAtlasBookmarksStrings.Fmt(TAtlasBookmarksTextId.QuickBookmarkTipJump,
      [ShortCutToText(TShortCut(mKey))]);
  end;
end;

class procedure TAtlasIdeQuickTip.TipText(const AMarks: TArray<TAtlasBookmark>; AJumpKey: Word;
  out ATitle, AText: string);
var
  mMark: TAtlasBookmark;
begin
  ATitle := '';
  AText := '';
  if Length(AMarks) = 0 then
  begin
    Exit;
  end;
  if Length(AMarks) > 1 then
  begin
    ATitle := TAtlasBookmarksStrings.Fmt(TAtlasBookmarksTextId.QuickBookmarkTipMore, [Length(AMarks)]);
  end
  else if AMarks[0].Number > 0 then
  begin
    ATitle := TAtlasBookmarksStrings.Fmt(TAtlasBookmarksTextId.QuickBookmarkTipTitle, [AMarks[0].Number]);
  end
  else
  begin
    ATitle := TAtlasBookmarksStrings.Text(TAtlasBookmarksTextId.QuickBookmarkTipUnnumbered);
  end;
  for mMark in AMarks do
  begin
    if AText <> '' then
    begin
      AText := AText + #10;
    end;
    AText := AText + TipLine(mMark, AJumpKey);
  end;
end;

{ TAtlasIdeQuickMenu }

constructor TAtlasIdeQuickMenu.Create;
begin
  inherited Create;
  FMenu := TPopupMenu.Create(nil);
end;

destructor TAtlasIdeQuickMenu.Destroy;
begin
  FMenu.Free;
  inherited Destroy;
end;

function TAtlasIdeQuickMenu.AddItem(AParent: TMenuItem; const ACaption: string; ATag: Integer): TMenuItem;
begin
  Result := TMenuItem.Create(FMenu);
  Result.Caption := ACaption;
  Result.Tag := ATag;
  Result.OnClick := MenuClick;
  AParent.Add(Result);
end;

procedure TAtlasIdeQuickMenu.Show(const AFileName: string; ALine: Integer; const AMarks: TArray<TAtlasBookmark>;
  const APoint: TPoint);
var
  mNumbers, mItem: TMenuItem;
  mTargets: TArray<string>;
  mNumber, mCurrent: Integer;
begin
  FMenu.Items.Clear;
  FFileName := AFileName;
  FLine := ALine;
  mCurrent := 0;
  if Length(AMarks) > 0 then
  begin
    mCurrent := AMarks[0].Number;
  end;
  mTargets := TAtlasIdeQuickBookmarks.NumberTargets(AFileName);
  mNumbers := AddItem(FMenu.Items, TAtlasBookmarksStrings.Text(TAtlasBookmarksTextId.QuickBookmarkMenuNumber), 0);
  mNumbers.OnClick := nil;
  for mNumber := 1 to TAtlasQuickBookmarks.MaxNumber do
  begin
    // Belegte Nummern zeigen ihr Ziel; die eigene ist abgehakt (Klick nimmt sie weg).
    if (mNumber < Length(mTargets)) and (mTargets[mNumber] <> '') and (mNumber <> mCurrent) then
    begin
      mItem := AddItem(mNumbers, TAtlasBookmarksStrings.Fmt(TAtlasBookmarksTextId.QuickBookmarkMenuNumberUsed,
        [mNumber, mTargets[mNumber]]), mNumber);
    end
    else
    begin
      mItem := AddItem(mNumbers, '&' + IntToStr(mNumber), mNumber);
    end;
    mItem.Checked := mNumber = mCurrent;
  end;
  AddItem(FMenu.Items, TAtlasBookmarksStrings.Text(TAtlasBookmarksTextId.QuickBookmarkMenuName), MenuName);
  mItem := AddItem(FMenu.Items, TAtlasBookmarksStrings.Text(TAtlasBookmarksTextId.QuickBookmarkMenuRemove),
    MenuRemove);
  mItem.Enabled := Length(AMarks) > 0;
  mItem := AddItem(FMenu.Items, TAtlasBookmarksStrings.Text(TAtlasBookmarksTextId.QuickBookmarkMenuRemoveFile),
    MenuRemoveFile);
  mItem.Enabled := TAtlasIdeQuickBookmarks.HasColumnMarks(AFileName);
  AddItem(FMenu.Items, '-', -1).OnClick := nil;
  AddItem(FMenu.Items, TAtlasBookmarksStrings.Text(TAtlasBookmarksTextId.QuickBookmarkMenuWindow), MenuWindow);
  FMenu.Popup(APoint.X, APoint.Y);
end;

procedure TAtlasIdeQuickMenu.MenuClick(Sender: TObject);
var
  mCommand, mLine: Integer;
  mFileName: string;
begin
  mCommand := TMenuItem(Sender).Tag;
  mFileName := FFileName;
  mLine := FLine;
  TAtlasGuard.Run(TAtlasFeature.QuickBookmarks,
    procedure
    begin
      case mCommand of
        1..TAtlasQuickBookmarks.MaxNumber:
          TAtlasIdeQuickBookmarks.ColumnAssign(mFileName, mLine, mCommand);
        MenuName:
          TAtlasIdeQuickBookmarks.ColumnName(mFileName, mLine);
        MenuRemove:
          TAtlasIdeQuickBookmarks.ColumnRemove(mFileName, mLine);
        MenuRemoveFile:
          TAtlasIdeQuickBookmarks.ColumnRemoveFile(mFileName);
        MenuWindow:
          TAtlasIdeBookmarks.ShowWindow;
      end;
    end);
end;

end.
