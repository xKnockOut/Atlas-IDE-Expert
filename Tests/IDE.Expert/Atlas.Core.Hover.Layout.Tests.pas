unit Atlas.Core.Hover.Layout.Tests;

// Tests für den Satz des Hover-Tooltips ohne VCL (P-09). Die erwarteten Zahlen
// sind aus dem bisherigen Render (Atlas.UI.Hover.Tip vor P-09) mit denselben
// Messwerten nachgerechnet; so bleibt das Aussehen festgehalten.
// Messwerte: Breite je Zeichen UI 7, Editorschrift 8 (halbfett 9), klein 6;
// Zeilenhöhe UI 15, Editorschrift 16, klein UI 13, klein Editorschrift 12; 96 dpi.

interface

uses
  DUnitX.TestFramework,
  System.Types,
  Atlas.Core.Hover.Contract,
  Atlas.Core.Hover.History,
  Atlas.Core.Hover.Layout;

type
  [TestFixture]
  THoverLayoutTests = class
  private
    function Input(const AView: TAtlasHoverView; AWidth: Integer): TAtlasHoverInput;
    function Build(const AView: TAtlasHoverView; AWidth: Integer): TAtlasHoverLayout; overload;
    function Build(const AInput: TAtlasHoverInput): TAtlasHoverLayout; overload;
    function View(const ADeclaration: string): TAtlasHoverView;
    procedure CheckRect(const AExpected, AActual: TRect; const AWhat: string);
    function CountKind(const ALayout: TAtlasHoverLayout; AKind: TAtlasHoverItemKind): Integer;
    function FirstKind(const ALayout: TAtlasHoverLayout; AKind: TAtlasHoverItemKind): Integer;
  public
    [Test]
    procedure DeclarationOnlyHasOneTextLine;
    [Test]
    procedure LongDeclarationWrapsWithIndent;
    [Test]
    procedure ProblemsProduceBlockAndBar;
    [Test]
    procedure PathChipsProduceHits;
    [Test]
    procedure PinnedShowsActions;
    [Test]
    procedure AnchorMovesLastBandDown;
    [Test]
    procedure ChainProducesChipsAndHits;
    [Test]
    procedure HeightGrowsWithDocHeight;
    [Test]
    procedure HitAtFindsActionRect;
    [Test]
    procedure BuildIsDeterministic;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Style.Palette,
  Atlas.Core.Style.Wrap,
  Atlas.Core.Problems.Contract;

type
  TFakeMeasure = class(TInterfacedObject, IAtlasHoverMeasure)
  private
    FDeclaration: string;
    function Cum: TArray<Integer>;
  public
    constructor Create(const ADeclaration: string);
    function TextWidth(const AFace: TAtlasHoverFace; const AText: string): Integer;
    function TextHeight(const AFace: TAtlasHoverFace): Integer;
    function BlockHeight(const AText: string; AWidth: Integer): Integer;
    function DeclarationWidth(AFrom, ATill: Integer): Integer;
    function DeclarationLines(AWidth, AIndent: Integer): TArray<TPoint>;
  end;

constructor TFakeMeasure.Create(const ADeclaration: string);
begin
  inherited Create;
  FDeclaration := ADeclaration;
end;

function TFakeMeasure.Cum: TArray<Integer>;
var
  Index: Integer;
begin
  Result := nil;
  SetLength(Result, Length(FDeclaration) + 1);
  for Index := 0 to Length(FDeclaration) do
    Result[Index] := 8 * Index;
end;

function TFakeMeasure.TextWidth(const AFace: TAtlasHoverFace; const AText: string): Integer;
begin
  case AFace.Font of
    TAtlasHoverFont.Ui:
      Result := 7 * Length(AText);
    TAtlasHoverFont.Mono:
      if AFace.Bold then
        Result := 9 * Length(AText)
      else
        Result := 8 * Length(AText);
  else
    Result := 6 * Length(AText);
  end;
end;

function TFakeMeasure.TextHeight(const AFace: TAtlasHoverFace): Integer;
begin
  case AFace.Font of
    TAtlasHoverFont.Ui:
      Result := 15;
    TAtlasHoverFont.Mono:
      Result := 16;
    TAtlasHoverFont.SmallUi:
      Result := 13;
  else
    Result := 12;
  end;
end;

function TFakeMeasure.BlockHeight(const AText: string; AWidth: Integer): Integer;
begin
  Result := 15 * ((7 * Length(AText) + AWidth - 1) div AWidth);
end;

function TFakeMeasure.DeclarationWidth(AFrom, ATill: Integer): Integer;
begin
  Result := 8 * (ATill - AFrom);
end;

function TFakeMeasure.DeclarationLines(AWidth, AIndent: Integer): TArray<TPoint>;
begin
  Result := TAtlasWrap.AtSpaces(FDeclaration, Cum, AWidth, AIndent);
end;

{ THoverLayoutTests }

function THoverLayoutTests.View(const ADeclaration: string): TAtlasHoverView;
var
  Data: TAtlasHoverData;
begin
  Data := Default(TAtlasHoverData);
  Data.Declaration := ADeclaration;
  Result := TAtlasHoverView.Create(Data);
end;

function THoverLayoutTests.Input(const AView: TAtlasHoverView; AWidth: Integer): TAtlasHoverInput;
begin
  Result := Default(TAtlasHoverInput);
  Result.View := AView;
  Result.Width := AWidth;
  Result.PPI := 96;
  Result.Colors := TAtlasColors.Light;
  Result.Texts.Pinned := 'pinned';
  Result.Texts.Inheritance := 'Vererbung';
  Result.Texts.TargetType := 'Ziel %s';
  Result.Texts.Navigate := 'Go';
  Result.Texts.Usages := 'Us';
  Result.Texts.UsagesCount := '%d Us';
  Result.Texts.Copy := 'Cp';
  Result.Texts.CopySelection := 'Sel';
  Result.Texts.Help := 'H';
  Result.Texts.KeyUsages := 'U';
  Result.Texts.KeyCopy := 'C';
  Result.Texts.SourceAtlas := 'Atlas';
  Result.Texts.SourceCompiler := 'dcc';
  Result.Texts.SourceInactive := 'inaktiv';
  Result.Texts.Stale := 'alt';
end;

function THoverLayoutTests.Build(const AInput: TAtlasHoverInput): TAtlasHoverLayout;
begin
  Result := TAtlasHoverLayout.Build(AInput, TFakeMeasure.Create(AInput.View.Data.Declaration));
end;

function THoverLayoutTests.Build(const AView: TAtlasHoverView; AWidth: Integer): TAtlasHoverLayout;
begin
  Result := Build(Input(AView, AWidth));
end;

procedure THoverLayoutTests.CheckRect(const AExpected, AActual: TRect; const AWhat: string);
begin
  Assert.AreEqual(AExpected.Left, AActual.Left, AWhat + ' links');
  Assert.AreEqual(AExpected.Top, AActual.Top, AWhat + ' oben');
  Assert.AreEqual(AExpected.Right, AActual.Right, AWhat + ' rechts');
  Assert.AreEqual(AExpected.Bottom, AActual.Bottom, AWhat + ' unten');
end;

function THoverLayoutTests.CountKind(const ALayout: TAtlasHoverLayout; AKind: TAtlasHoverItemKind): Integer;
var
  Item: TAtlasHoverItem;
begin
  Result := 0;
  for Item in ALayout.Items do
    if Item.Kind = AKind then
      Inc(Result);
end;

function THoverLayoutTests.FirstKind(const ALayout: TAtlasHoverLayout; AKind: TAtlasHoverItemKind): Integer;
var
  Index: Integer;
begin
  for Index := 0 to High(ALayout.Items) do
    if ALayout.Items[Index].Kind = AKind then
      Exit(Index);
  Result := -1;
end;

procedure THoverLayoutTests.DeclarationOnlyHasOneTextLine;
var
  Layout: TAtlasHoverLayout;
begin
  Layout := Build(View('x: Integer'), 300);
  Assert.AreEqual(1, Integer(Length(Layout.Items)));
  Assert.AreEqual(0, Integer(Length(Layout.Hits)));
  Assert.IsTrue(Layout.Items[0].Kind = TAtlasHoverItemKind.Styled);
  CheckRect(Rect(11, 8, 289, 26), Layout.Items[0].Rect, 'Deklaration');
  Assert.AreEqual(0, Layout.Items[0].From);
  Assert.AreEqual(10, Layout.Items[0].Till);
  Assert.AreEqual(32, Layout.Height);
end;

procedure THoverLayoutTests.LongDeclarationWrapsWithIndent;
var
  Layout: TAtlasHoverLayout;
begin
  Layout := Build(View('procedure Foo(A: Integer; B: string)'), 200);
  Assert.AreEqual(2, CountKind(Layout, TAtlasHoverItemKind.Styled));
  CheckRect(Rect(11, 8, 189, 26), Layout.Items[0].Rect, 'Zeile 1');
  Assert.AreEqual(17, Layout.Items[0].Till);
  CheckRect(Rect(27, 26, 189, 44), Layout.Items[1].Rect, 'Zeile 2 eingerückt');
  Assert.AreEqual(17, Layout.Items[1].From);
  Assert.AreEqual(36, Layout.Items[1].Till);
  Assert.AreEqual(50, Layout.Height);
end;

procedure THoverLayoutTests.ProblemsProduceBlockAndBar;
var
  HoverView: TAtlasHoverView;
  Problem: TAtlasProblem;
  Layout: TAtlasHoverLayout;
  Bar: Integer;
  Colors: TAtlasColors;
begin
  HoverView := View('');
  Problem := Default(TAtlasProblem);
  Problem.Message := 'x';
  Problem.Severity := TAtlasProblemSeverity.Error;
  HoverView.Problems := [Problem];
  Layout := Build(HoverView, 300);
  Assert.IsTrue(Layout.Items[0].Kind = TAtlasHoverItemKind.Block);
  CheckRect(Rect(20, 8, 289, 23), Layout.Items[0].Rect, 'Meldung');
  Assert.IsTrue(Layout.Items[1].Kind = TAtlasHoverItemKind.Text);
  Assert.AreEqual('Atlas', Layout.Items[1].Text);
  Assert.AreEqual(20, Layout.Items[1].Rect.Left);
  Assert.AreEqual(25, Layout.Items[1].Rect.Top);
  Bar := FirstKind(Layout, TAtlasHoverItemKind.RoundFill);
  Assert.IsTrue(Bar >= 0);
  CheckRect(Rect(11, 9, 14, 37), Layout.Items[Bar].Rect, 'Farbbalken');
  Colors := TAtlasColors.Light;
  Assert.AreEqual(Colors.Error, Layout.Items[Bar].Color);
  // Ohne Deklaration endet der Tooltip nach den Problemen.
  Assert.AreEqual(46, Layout.Height);
end;

procedure THoverLayoutTests.PathChipsProduceHits;
var
  HoverView: TAtlasHoverView;
  First, Second: TAtlasHoverPathItem;
  Layout: TAtlasHoverLayout;
  Index: Integer;
  Found: Boolean;
begin
  HoverView := View('x');
  HoverView.Pinned := True;
  HoverView.CanGoBack := True;
  First.Index := 0;
  First.Caption := 'TA';
  Second.Index := -1;
  Second.Caption := 'TB';
  HoverView.Path := [First, Second];
  Layout := Build(HoverView, 300);
  Assert.AreEqual(2, Integer(Length(Layout.Hits)));
  Assert.IsTrue(Layout.Hits[0].Kind = TAtlasHoverHitKind.Back);
  CheckRect(Rect(8, 5, 30, 25), Layout.Hits[0].Rect, 'Zurück');
  Assert.IsTrue(Layout.Hits[1].Kind = TAtlasHoverHitKind.Path);
  Assert.AreEqual(0, Layout.Hits[1].Index);
  CheckRect(Rect(36, 7, 52, 23), Layout.Hits[1].Rect, 'Pfad TA');
  // „angeheftet“ rechtsbündig, weil Platz ist.
  Found := False;
  for Index := 0 to High(Layout.Items) do
    if Layout.Items[Index].Text = 'pinned' then
    begin
      Found := True;
      Assert.AreEqual(253, Layout.Items[Index].Rect.Left);
      Assert.AreEqual(8, Layout.Items[Index].Rect.Top);
    end;
  Assert.IsTrue(Found);
  Assert.AreEqual(38, Layout.Items[FirstKind(Layout, TAtlasHoverItemKind.Styled)].Rect.Top);
  Assert.AreEqual(62, Layout.Height);
end;

function ActionsView: TAtlasHoverView;
var
  Data: TAtlasHoverData;
begin
  Data := Default(TAtlasHoverData);
  Data.Declaration := 'x';
  Data.Location.Name := 'x';
  Data.Location.FileName := 'C:\a\U.pas';
  Data.Location.Line := 4;
  Result := TAtlasHoverView.Create(Data);
end;

procedure THoverLayoutTests.PinnedShowsActions;
var
  Layout: TAtlasHoverLayout;
  Index: Integer;
  Found: Boolean;
begin
  Layout := Build(ActionsView, 300);
  // Hilfe ohne DocWiki: keine Klickfläche.
  Assert.AreEqual(3, Integer(Length(Layout.Hits)));
  for Index := 0 to 2 do
  begin
    Assert.IsTrue(Layout.Hits[Index].Kind = TAtlasHoverHitKind.Action);
    Assert.AreEqual(Index, Layout.Hits[Index].Index);
  end;
  CheckRect(Rect(11, 60, 47, 73), Layout.Hits[0].Rect, 'Gehe zu');
  CheckRect(Rect(61, 60, 85, 73), Layout.Hits[1].Rect, 'Verwendungen');
  CheckRect(Rect(99, 60, 123, 73), Layout.Hits[2].Rect, 'Kopieren');
  // Fundort rechtsbündig in der Kopfzeile.
  Found := False;
  for Index := 0 to High(Layout.Items) do
    if Layout.Items[Index].Text = 'U.pas : 5' then
    begin
      Found := True;
      Assert.AreEqual(235, Layout.Items[Index].Rect.Left);
      Assert.AreEqual(10, Layout.Items[Index].Rect.Top);
    end;
  Assert.IsTrue(Found);
  // Randfläche mit Linie oben vor dem Inhalt.
  Assert.AreEqual(Layout.AnchorItem, FirstKind(Layout, TAtlasHoverItemKind.Fill));
  CheckRect(Rect(0, 54, 300, 79), Layout.Items[Layout.AnchorItem].Rect, 'Randfläche');
  Assert.AreEqual(79, Layout.Height);
end;

procedure THoverLayoutTests.AnchorMovesLastBandDown;
var
  Layout: TAtlasHoverLayout;
begin
  Layout := Build(ActionsView, 300);
  Layout.Anchor(200);
  Assert.AreEqual(181, Layout.Hits[0].Rect.Top);
  Assert.AreEqual(175, Layout.Items[Layout.AnchorItem].Rect.Top);
  // Wiederholbar, nie über die eigene Lage nach oben.
  Layout.Anchor(200);
  Assert.AreEqual(181, Layout.Hits[0].Rect.Top);
  Layout.Anchor(50);
  Assert.AreEqual(60, Layout.Hits[0].Rect.Top);
end;

procedure THoverLayoutTests.ChainProducesChipsAndHits;
var
  HoverView: TAtlasHoverView;
  First, Second: TAtlasHoverTypeRef;
  Layout: TAtlasHoverLayout;
begin
  HoverView := View('x');
  First := Default(TAtlasHoverTypeRef);
  First.Name := 'TA';
  Second := Default(TAtlasHoverTypeRef);
  Second.Name := 'TObject';
  HoverView.Data.Ancestors := [First, Second];
  Layout := Build(HoverView, 300);
  Assert.AreEqual(2, Integer(Length(Layout.Hits)));
  Assert.IsTrue(Layout.Hits[0].Kind = TAtlasHoverHitKind.Ancestor);
  CheckRect(Rect(11, 58, 39, 76), Layout.Hits[0].Rect, 'TA');
  Assert.AreEqual(1, Layout.Hits[1].Index);
  CheckRect(Rect(63, 58, 131, 76), Layout.Hits[1].Rect, 'TObject');
  Assert.AreEqual(2, CountKind(Layout, TAtlasHoverItemKind.Frame));
  // Ohne Fundort ist die Kette die letzte Randfläche.
  Assert.IsTrue(Layout.AnchorItem >= 0);
  Assert.AreEqual(84, Layout.Height);
end;

procedure THoverLayoutTests.HeightGrowsWithDocHeight;
var
  HoverInput: TAtlasHoverInput;
  Layout: TAtlasHoverLayout;
begin
  HoverInput := Input(View('x'), 300);
  HoverInput.HasDoc := True;
  HoverInput.DocHeight := 100;
  Layout := Build(HoverInput);
  Assert.AreEqual(11, Layout.DocLeft);
  Assert.AreEqual(39, Layout.DocTop);
  Assert.AreEqual(146, Layout.Height);
  HoverInput.DocHeight := 40;
  Assert.AreEqual(86, Build(HoverInput).Height);
end;

procedure THoverLayoutTests.HitAtFindsActionRect;
var
  Layout: TAtlasHoverLayout;
begin
  Layout := Build(ActionsView, 300);
  Assert.AreEqual(0, Layout.HitAt(Point(20, 65)));
  Assert.AreEqual(2, Layout.HitAt(Point(100, 60)));
  Assert.AreEqual(-1, Layout.HitAt(Point(5, 5)));
  Assert.IsTrue(Layout.IsHot(1, TAtlasHoverHitKind.Action, 1));
  Assert.IsFalse(Layout.IsHot(1, TAtlasHoverHitKind.Action, 0));
  Assert.IsFalse(Layout.IsHot(-1, TAtlasHoverHitKind.Action, 1));
end;

procedure THoverLayoutTests.BuildIsDeterministic;
var
  A, B: TAtlasHoverLayout;
  Index: Integer;
begin
  A := Build(ActionsView, 300);
  B := Build(ActionsView, 300);
  Assert.AreEqual(Integer(Length(A.Items)), Integer(Length(B.Items)));
  for Index := 0 to High(A.Items) do
  begin
    CheckRect(A.Items[Index].Rect, B.Items[Index].Rect, 'Baustein');
    Assert.AreEqual(A.Items[Index].Text, B.Items[Index].Text);
  end;
  Assert.AreEqual(A.Height, B.Height);
end;

initialization
  TDUnitX.RegisterTestFixture(THoverLayoutTests);

end.
