unit Atlas.Core.Settings.Plugin.Bookmarks;

// Einstellungen des IDE-Plugins, Bereich Lesezeichen (bookmarks.*) (#227, ADR 0017):
// Felder, Vorgaben, Grenzen, Lesen und Schreiben. TAtlasPluginSettings (Atlas.Core.Settings.Plugin)
// fasst die Bereiche zusammen und reicht die Felder als Eigenschaften durch.

interface

uses
  Atlas.Core.Settings.Plugin.Store;

const
  /// <summary>Höchste Wartezeit in ms auf den zweiten Teil der Faltungsakkorde (#1104,
  /// bookmarks.quick.chordWait).</summary>
  cMaxQuickChordWait = 5000;

type
  /// <summary>Plugin-Einstellungen: Lesezeichen und Schnell-Lesezeichen.</summary>
  TAtlasPluginBookmarksSettings = record
    /// <summary>Benannte Lesezeichen (#622, bookmarks.named): Befehle, Seitenfenster „Lesezeichen“ und Symbol in der
    /// Rinne; aus = die Funktion ruht, die nummerierten Lesezeichen der IDE bleiben unberührt.</summary>
    BookmarksNamed: Boolean;
    /// <summary>Lesezeichen im Repository für das Team speichern (#622, bookmarks.shared): atlas-bookmarks.json
    /// statt der lokalen .atlas-bookmarks.json neben der .dproj.</summary>
    BookmarksShared: Boolean;
    /// <summary>Schnelle Lesezeichen, nummeriert und unnummeriert (#1104, bookmarks.quick); Hauptschalter.</summary>
    QuickBookmarks: Boolean;
    /// <summary>Spalte links der Zeilennummern mit den Markern (#1104, bookmarks.quick.gutter).</summary>
    QuickBookmarksGutter: Boolean;
    /// <summary>Linksklick in die Spalte setzt und entfernt Lesezeichen (#1104, bookmarks.quick.gutterClick).
    /// </summary>
    QuickBookmarksGutterClick: Boolean;
    /// <summary>Tasten für Nummern 1–9 von der IDE übernehmen (#1104, bookmarks.quick.numberedKeys).</summary>
    QuickBookmarksNumberedKeys: Boolean;
    /// <summary>Taste für unnummerierte Lesezeichen (#1104, bookmarks.quick.key); 0 = keine.</summary>
    QuickBookmarkKey: Integer;
    /// <summary>Wartezeit in ms auf den zweiten Faltungsakkordteil, 0 bis MaxQuickChordWait; 0 = die Taste bleibt
    /// bei der IDE (#1104, bookmarks.quick.chordWait).</summary>
    QuickBookmarkChordWait: Integer;
    /// <summary>Sprungbereich von Strg+1…9: project oder file (#1104, bookmarks.quick.scope).</summary>
    QuickBookmarksScope: string;
    /// <summary>Vorhandene IDE-Lesezeichen 1–9 übernehmen und dort entfernen (#1104, bookmarks.quick.importIde).
    /// </summary>
    QuickBookmarksImportIde: Boolean;
    /// <summary>Modul-Schalter bookmarks.enabled (#1454): Lesezeichen und Notizen; aus = die wirksamen Werte aller
    /// Einstellungen des Moduls sind
    /// „aus“ (TAtlasModuleSwitches), gespeichert bleiben sie.</summary>
    BookmarksEnabled: Boolean;
    /// <summary>Vorgaben.</summary>
    class function Defaults: TAtlasPluginBookmarksSettings; static;
    /// <summary>Werte in ihre Grenzen bringen.</summary>
    procedure Normalize;
    /// <summary>Werte über AIo lesen bzw. schreiben, jeden unter seinem Namen.</summary>
    procedure Exchange(const AIo: TAtlasSettingsExchange);
  end;

implementation

uses
  System.Math;

{ TAtlasPluginBookmarksSettings }

class function TAtlasPluginBookmarksSettings.Defaults: TAtlasPluginBookmarksSettings;
begin
  Result.BookmarksNamed := True;
  Result.BookmarksShared := False;
  Result.QuickBookmarks := True;
  Result.QuickBookmarksGutter := True;
  Result.QuickBookmarksGutterClick := True;
  Result.QuickBookmarksNumberedKeys := True;
  Result.QuickBookmarkKey := $604B; // Strg+Umschalt+K
  Result.QuickBookmarkChordWait := 800;
  Result.QuickBookmarksScope := 'project';
  Result.QuickBookmarksImportIde := True;
  Result.BookmarksEnabled := True;
end;

procedure TAtlasPluginBookmarksSettings.Normalize;
begin
  QuickBookmarkKey := EnsureRange(QuickBookmarkKey, 0, $FFFF);
  QuickBookmarkChordWait := EnsureRange(QuickBookmarkChordWait, 0, cMaxQuickChordWait);
  QuickBookmarksScope := Choice(QuickBookmarksScope, cAtlasQuickBookmarkScopes);
end;

procedure TAtlasPluginBookmarksSettings.Exchange(const AIo: TAtlasSettingsExchange);
begin
  AIo.Flag('BookmarksNamed', BookmarksNamed);
  AIo.Flag('BookmarksShared', BookmarksShared);
  AIo.Flag('QuickBookmarks', QuickBookmarks);
  AIo.Flag('QuickBookmarksGutter', QuickBookmarksGutter);
  AIo.Flag('QuickBookmarksGutterClick', QuickBookmarksGutterClick);
  AIo.Flag('QuickBookmarksNumberedKeys', QuickBookmarksNumberedKeys);
  AIo.Number('QuickBookmarkKey', QuickBookmarkKey);
  AIo.Number('QuickBookmarkChordWait', QuickBookmarkChordWait);
  AIo.Text('QuickBookmarksScope', QuickBookmarksScope);
  AIo.Flag('QuickBookmarksImportIde', QuickBookmarksImportIde);
  AIo.Flag('BookmarksEnabled', BookmarksEnabled);
end;

end.
