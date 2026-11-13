unit Atlas.IDE.Tests.CoveredByList;

// Liste der Tests einer Marke „getestet von“ (#1778, Strg+Klick): ein
// Kontextmenü mit Überschrift und je Test einem Eintrag, der zum Kopf der
// Testmethode springt.

interface

uses
  System.Types,
  Vcl.Menus,
  Atlas.Core.Tests.CoveredBy;

type
  TAtlasIdeCoveredByList = class
  private
    FMenu: TPopupMenu;
    FListed: TArray<TAtlasCoveredTest>;
    procedure ItemClick(Sender: TObject);
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>Tests ATests als Menü an AAt (Bildschirm) zeigen.</summary>
    procedure Show(const ATests: TArray<TAtlasCoveredTest>; const AAt: TPoint);
  end;

implementation

uses
  System.SysUtils,
  Atlas.UI.Tests.Strings,
  Atlas.IDE.Foundation.Navigation;

constructor TAtlasIdeCoveredByList.Create;
begin
  inherited Create;
  FMenu := TPopupMenu.Create(nil);
end;

destructor TAtlasIdeCoveredByList.Destroy;
begin
  FMenu.Free;
  FListed := nil;
  inherited Destroy;
end;

procedure TAtlasIdeCoveredByList.Show(const ATests: TArray<TAtlasCoveredTest>; const AAt: TPoint);
var
  mItem: TMenuItem;
  mIndex: Integer;
begin
  FListed := ATests;
  FMenu.Items.Clear;
  mItem := TMenuItem.Create(FMenu);
  mItem.Caption := TAtlasTestsStrings.Text(TAtlasTestsTextId.CoveredByListTitle);
  mItem.Enabled := False;
  FMenu.Items.Add(mItem);
  for mIndex := 0 to High(ATests) do
  begin
    mItem := TMenuItem.Create(FMenu);
    mItem.Caption := StringReplace(ATests[mIndex].Name, '&', '&&', [rfReplaceAll]);
    mItem.Tag := mIndex;
    mItem.OnClick := ItemClick;
    FMenu.Items.Add(mItem);
  end;
  FMenu.Popup(AAt.X, AAt.Y);
end;

procedure TAtlasIdeCoveredByList.ItemClick(Sender: TObject);
var
  mIndex: Integer;
begin
  mIndex := (Sender as TMenuItem).Tag;
  if (mIndex >= 0) and (mIndex <= High(FListed)) then
  begin
    TAtlasIdeNavigation.GoToLocation(FListed[mIndex].FileName, FListed[mIndex].Line, 0);
  end;
end;

end.
