unit Atlas.UI.Settings.Page.TestSupport;

// Gemeinsame Hilfen der Tests der Einstellungsseite (Atlas.UI.Settings.Page.*.Tests) und der Abschnitte der
// Module (#1456): Ein Test meldet die Abschnitte eines Moduls an wie dessen Composition und gibt sie im TearDown
// wieder ab.

interface

uses
  Atlas.Core.Modules.Contract,
  Atlas.UI.Settings.Contract,
  Atlas.UI.Settings.ChoiceBox,
  Atlas.UI.Settings.Section,
  Atlas.UI.Settings.Page,
  Vcl.Controls,
  Vcl.StdCtrls,
  Vcl.Forms,
  Vcl.ComCtrls;

/// <summary>Erzeugt die Seite einmal ohne und einmal mit Fenster, damit einmalige VCL-Daten keinem Test
/// angerechnet werden.</summary>
procedure WarmUpSettingsPage;

/// <summary>Reiter, auf dem AControl liegt; nil ohne.</summary>
function SheetOf(AControl: TControl): TTabSheet;

/// <summary>Kontrollkästchen der Plugin-Einstellung AName (Registry-Name); Fehler, wenn es keins ist.</summary>
function CheckOf(APage: TAtlasSettingsPage; const AName: string): TCheckBox;

/// <summary>Eingabefeld der Plugin-Einstellung AName (Registry-Name); Fehler, wenn es keins ist.</summary>
function EditOf(APage: TAtlasSettingsPage; const AName: string): TEdit;

/// <summary>Auswahl der Plugin-Einstellung AName (Registry-Name); Fehler, wenn es keine ist.</summary>
function ChoiceOf(APage: TAtlasSettingsPage; const AName: string): TAtlasChoiceBox;

/// <summary>Meldet die Abschnitte der Klassen an wie die Composition eines Moduls (je Seite ein neuer Abschnitt).
/// </summary>
function ProvideSections(const AClasses: array of TAtlasSettingsSectionClass): TArray<IAtlasRegistration>;

/// <summary>Meldet ASection selbst an: Jede Seite bekommt diesen einen Abschnitt, damit der Test seine eigenen
/// Elemente erreicht. Nur für Tests mit einer Seite.</summary>
function ProvideSection(const ASection: IAtlasSettingsSection): IAtlasRegistration;

/// <summary>Gibt alle Anmeldungen ab und leert die Liste.</summary>
procedure RevokeAll(var ARegistrations: TArray<IAtlasRegistration>);

/// <summary>Knoten der obersten Ebene im Navigationsbaum der Seite.</summary>
function TopLevelNodes(APage: TAtlasSettingsPage): TArray<TTreeNode>;

/// <summary>Knoten des Baums, der ASheet zeigt (wählt dazu die Knoten nacheinander); nil ohne.</summary>
function TreeNodeOf(APage: TAtlasSettingsPage; ASheet: TTabSheet): TTreeNode;

implementation

uses
  Atlas.Core.Modules.Registry;

type
  TAtlasFixedSectionProvider = class(TInterfacedObject, IAtlasSettingsSectionProvider)
  private
    FSection: IAtlasSettingsSection;
  public
    constructor Create(const ASection: IAtlasSettingsSection);
    function CreateSection: IAtlasSettingsSection;
  end;

constructor TAtlasFixedSectionProvider.Create(const ASection: IAtlasSettingsSection);
begin
  inherited Create;
  FSection := ASection;
end;

function TAtlasFixedSectionProvider.CreateSection: IAtlasSettingsSection;
begin
  Result := FSection;
end;

procedure WarmUpSettingsPage;
var
  Host: TForm;
  Page: TAtlasSettingsPage;
begin
  TAtlasSettingsPage.Create(nil).Free;
  // Auch mit Fenster (Reiter, PageControl): einmalige VCL-Daten nicht dem ersten Test anrechnen.
  Host := TForm.CreateNew(nil);
  try
    Page := TAtlasSettingsPage.Create(Host);
    Page.Parent := Host;
    Page.HandleNeeded;
  finally
    Host.Free;
  end;
end;

function SheetOf(AControl: TControl): TTabSheet;
begin
  while (AControl <> nil) and not (AControl is TTabSheet) do
  begin
    AControl := AControl.Parent;
  end;
  Result := TTabSheet(AControl);
end;

function CheckOf(APage: TAtlasSettingsPage; const AName: string): TCheckBox;
begin
  Result := APage.ControlOfSetting(AName) as TCheckBox;
end;

function EditOf(APage: TAtlasSettingsPage; const AName: string): TEdit;
begin
  Result := APage.ControlOfSetting(AName) as TEdit;
end;

function ChoiceOf(APage: TAtlasSettingsPage; const AName: string): TAtlasChoiceBox;
begin
  Result := APage.ControlOfSetting(AName) as TAtlasChoiceBox;
end;

function ProvideSections(const AClasses: array of TAtlasSettingsSectionClass): TArray<IAtlasRegistration>;
var
  mClass: TAtlasSettingsSectionClass;
begin
  Result := nil;
  for mClass in AClasses do
  begin
    Result := Result + [AtlasModuleRegistry.Provide(IAtlasSettingsSectionProvider,
      TAtlasSettingsSectionFactory.Create(mClass) as IAtlasSettingsSectionProvider)];
  end;
end;

function ProvideSection(const ASection: IAtlasSettingsSection): IAtlasRegistration;
begin
  Result := AtlasModuleRegistry.Provide(IAtlasSettingsSectionProvider,
    TAtlasFixedSectionProvider.Create(ASection) as IAtlasSettingsSectionProvider);
end;

procedure RevokeAll(var ARegistrations: TArray<IAtlasRegistration>);
var
  mRegistration: IAtlasRegistration;
begin
  for mRegistration in ARegistrations do
  begin
    mRegistration.Revoke;
  end;
  ARegistrations := nil;
end;

function TopLevelNodes(APage: TAtlasSettingsPage): TArray<TTreeNode>;
var
  Index: Integer;
begin
  Result := nil;
  for Index := 0 to APage.Navigation.Items.Count - 1 do
  begin
    if APage.Navigation.Items[Index].Level = 0 then
    begin
      Result := Result + [APage.Navigation.Items[Index]];
    end;
  end;
end;

function TreeNodeOf(APage: TAtlasSettingsPage; ASheet: TTabSheet): TTreeNode;
var
  mIndex: Integer;
begin
  for mIndex := 0 to APage.Navigation.Items.Count - 1 do
  begin
    Result := APage.Navigation.Items[mIndex];
    APage.Navigation.OnChange(APage.Navigation, Result);
    if APage.Pages.ActivePage = ASheet then
    begin
      Exit;
    end;
  end;
  Result := nil;
end;

end.
