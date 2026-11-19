unit Atlas.IDE.Welcome.Adapters.Layouts;

// „Seite anpassen“ (#767) für die Tafeln: reicht IAtlasWelcomeArrangeSource an die Layouts der Seite
// (Atlas.IDE.Welcome.Layouts) weiter. Die Composition legt ihn an und gibt ihn der Steuerung mit.

interface

uses
  System.Types,
  Atlas.Core.Welcome.Contract,
  Atlas.UI.Welcome.Contract,
  Atlas.IDE.Welcome.Layouts;

type
  TAtlasIdeWelcomeArrange = class(TInterfacedObject, IAtlasWelcomeArrangeSource)
  private
    FLayouts: TAtlasIdeWelcomeLayouts;
    // Hält die Layouts am Leben, solange eine Tafel diese Quelle hält.
    FLayoutsRef: IInterface;
  public
    constructor Create(ALayouts: TAtlasIdeWelcomeLayouts);
    { IAtlasWelcomeArrangeSource }
    function CanCustomize: Boolean;
    function Editing: Boolean;
    procedure SetEditing(AOn: Boolean);
    function LayoutNames: TArray<string>;
    function ActiveLayout: string;
    function Catalog: TArray<TAtlasWelcomeCatalogEntry>;
    procedure Arrange(const ALayout: TAtlasWelcomeLayout);
    procedure ShowSection(const AId: string; AColumn: Integer; const ABefore: string);
    procedure HideSection(const AId: string);
    procedure HideSectionAt(const AId: string; const APoint: TPoint);
    procedure ShowSectionSettings(const AId: string);
    procedure SwitchLayout(const AName: string);
    function AddLayout(const AName: string): Boolean;
    function RenameLayout(const AName: string): Boolean;
    function DeleteLayout: Boolean;
    procedure ResetLayout;
  end;

implementation

{ TAtlasIdeWelcomeArrange }

constructor TAtlasIdeWelcomeArrange.Create(ALayouts: TAtlasIdeWelcomeLayouts);
begin
  inherited Create;
  FLayouts := ALayouts;
  FLayoutsRef := ALayouts;
end;

function TAtlasIdeWelcomeArrange.CanCustomize: Boolean;
begin
  Result := FLayouts.CanCustomize;
end;

function TAtlasIdeWelcomeArrange.Editing: Boolean;
begin
  Result := FLayouts.Editing;
end;

procedure TAtlasIdeWelcomeArrange.SetEditing(AOn: Boolean);
begin
  FLayouts.SetEditing(AOn);
end;

function TAtlasIdeWelcomeArrange.LayoutNames: TArray<string>;
begin
  Result := FLayouts.LayoutNames;
end;

function TAtlasIdeWelcomeArrange.ActiveLayout: string;
begin
  Result := FLayouts.ActiveLayout;
end;

function TAtlasIdeWelcomeArrange.Catalog: TArray<TAtlasWelcomeCatalogEntry>;
begin
  Result := FLayouts.Catalog;
end;

procedure TAtlasIdeWelcomeArrange.Arrange(const ALayout: TAtlasWelcomeLayout);
begin
  FLayouts.Arrange(ALayout);
end;

procedure TAtlasIdeWelcomeArrange.ShowSection(const AId: string; AColumn: Integer; const ABefore: string);
begin
  FLayouts.ShowSection(AId, AColumn, ABefore);
end;

procedure TAtlasIdeWelcomeArrange.HideSection(const AId: string);
begin
  FLayouts.HideSection(AId);
end;

procedure TAtlasIdeWelcomeArrange.HideSectionAt(const AId: string; const APoint: TPoint);
begin
  FLayouts.HideSectionAt(AId, APoint);
end;

procedure TAtlasIdeWelcomeArrange.ShowSectionSettings(const AId: string);
begin
  FLayouts.ShowSectionSettings(AId);
end;

procedure TAtlasIdeWelcomeArrange.SwitchLayout(const AName: string);
begin
  FLayouts.SwitchLayout(AName);
end;

function TAtlasIdeWelcomeArrange.AddLayout(const AName: string): Boolean;
begin
  Result := FLayouts.AddLayout(AName);
end;

function TAtlasIdeWelcomeArrange.RenameLayout(const AName: string): Boolean;
begin
  Result := FLayouts.RenameLayout(AName);
end;

function TAtlasIdeWelcomeArrange.DeleteLayout: Boolean;
begin
  Result := FLayouts.DeleteLayout;
end;

procedure TAtlasIdeWelcomeArrange.ResetLayout;
begin
  FLayouts.ResetLayout;
end;

end.
