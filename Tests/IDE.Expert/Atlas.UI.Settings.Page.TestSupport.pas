unit Atlas.UI.Settings.Page.TestSupport;

// Gemeinsame Hilfen der Tests der Einstellungsseite (Atlas.UI.Settings.Page.*.Tests).

interface

uses
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

/// <summary>Knoten der obersten Ebene im Navigationsbaum der Seite.</summary>
function TopLevelNodes(APage: TAtlasSettingsPage): TArray<TTreeNode>;

implementation

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

end.
