unit Argus.IDE.Editor.Structure;

// Schaltet die Strukturhervorhebung der IDE ab, solange Argus eigene
// Blocklinien zeichnet (#514), und stellt sie wieder her, wenn sie aus sind.
// Es gibt dafür keine Open Tools API: Der Schalter steht in der Registry
// (<Basisschlüssel>\Editor\Highlight\Structural Highlighting, Enabled) und
// wird von der IDE beim Start gelesen. Ob Argus abgeschaltet hat, steht unter
// HKCU\Software\Argus\IdePlugin (IdeStructureDisabled).

interface

type
  TArgusIdeStructureSwitch = class
  public
    /// <summary>Gleicht den Schalter der IDE an; True, wenn er geändert wurde
    /// (wirkt nach dem nächsten Start der IDE).</summary>
    class function Apply(AOwnGuides: Boolean): Boolean; static;
    /// <summary>Apply nach den aktuellen Einstellungen; meldet eine Änderung im Meldungsfenster.</summary>
    class procedure Sync; static;
  end;

implementation

uses
  Winapi.Windows,
  System.SysUtils,
  System.Classes,
  System.Win.Registry,
  ToolsAPI,
  Argus.Core.Settings.Plugin,
  Argus.Core.Editor.Guides,
  Argus.UI.Strings,
  Argus.IDE.Settings.Store;

const
  StructureKey = '\Editor\Highlight\Structural Highlighting';
  MarkerName = 'IdeStructureDisabled';

class function TArgusIdeStructureSwitch.Apply(AOwnGuides: Boolean): Boolean;
var
  Services: IOTAServices;
  Registry: TRegistry;
  Key: string;
  State, Next: TArgusIdeStructure;
begin
  Result := False;
  if not Supports(BorlandIDEServices, IOTAServices, Services) then
    Exit;
  Key := Services.GetBaseRegistryKey + StructureKey;
  Registry := TRegistry.Create(KEY_READ or KEY_WRITE);
  try
    Registry.RootKey := HKEY_CURRENT_USER;
    try
      // Ohne den Schlüssel gilt die Vorgabe der IDE: eingeschaltet.
      State.Enabled := True;
      if Registry.OpenKey(Key, True) and Registry.ValueExists('Enabled') then
        State.Enabled := SameText(Registry.ReadString('Enabled'), 'True');
      Registry.CloseKey;
      State.DisabledByArgus := False;
      if Registry.OpenKey(ArgusRegistryKey, True) and Registry.ValueExists(MarkerName) then
        State.DisabledByArgus := Registry.ReadInteger(MarkerName) <> 0;
      Registry.CloseKey;
      Next := TArgusGuides.Switch(State, AOwnGuides);
      if Next.Enabled <> State.Enabled then
      begin
        if Registry.OpenKey(Key, True) then
        begin
          if Next.Enabled then
            Registry.WriteString('Enabled', 'True')
          else
            Registry.WriteString('Enabled', 'False');
          Result := True;
        end;
        Registry.CloseKey;
      end;
      if (Next.DisabledByArgus <> State.DisabledByArgus) and Registry.OpenKey(ArgusRegistryKey, True) then
      begin
        Registry.WriteInteger(MarkerName, Ord(Next.DisabledByArgus));
        Registry.CloseKey;
      end;
    except
      // Ohne Schreibrecht bleibt die IDE, wie sie ist.
      on ERegistryException do
        Result := False;
    end;
  finally
    Registry.Free;
  end;
end;

class procedure TArgusIdeStructureSwitch.Sync;
var
  Settings: TArgusPluginSettings;
  Own: Boolean;
  Text: string;
begin
  Settings := TArgusIdeSettings.Current;
  Own := Settings.PairColors and Settings.PairGuides;
  if not Apply(Own) then
    Exit;
  if Own then
    Text := TArgusStrings.Text(TArgusTextId.PairGuidesIdeOff)
  else
    Text := TArgusStrings.Text(TArgusTextId.PairGuidesIdeOn);
  // Beim Laden des Plugins ist das Meldungsfenster noch nicht bereit.
  TThread.ForceQueue(nil,
    procedure
    var
      Messages: IOTAMessageServices;
    begin
      if Supports(BorlandIDEServices, IOTAMessageServices, Messages) then
        Messages.AddTitleMessage(Text);
    end);
end;

end.
