unit BDLsp.Common.Projects.Contract;

// Contract des Platform-Features Projects: das ausgewertete Delphi-Projekt
// (.dproj) und die Auflösung von Unit-Namen zu Dateien.
//
// Pfade sind absolut. Die Bibliothekspfade der Delphi-Installation liefert
// ein ILibraryPathProvider; unter Windows liest ihn BDLsp.Windows aus der
// Registry, Tests geben feste Pfade vor.

interface

{$SCOPEDENUMS ON}

uses
  System.SysUtils,
  System.Generics.Collections;

type
  /// <summary>Eine Unit, die im Projekt mit Pfad eingetragen ist (DCCReference bzw. "uses X in 'pfad'").</summary>
  TProjectUnit = record
    Name: string;
    FileName: string;
  end;

  /// <summary>Ausgewertetes Projekt für eine Konfiguration und Plattform.</summary>
  TProjectInfo = record
    /// <summary>Absoluter Pfad der .dproj-Datei.</summary>
    FileName: string;
    /// <summary>Absoluter Pfad der Hauptdatei (.dpr, .dpk); leer, wenn nicht angegeben.</summary>
    MainSource: string;
    Config: string;
    Platform: string;
    /// <summary>Bedingte Symbole (DCC_Define), ohne Duplikate, in Großschreibung.</summary>
    Defines: TArray<string>;
    /// <summary>Suchpfade des Projekts (DCC_UnitSearchPath), absolut, vorhandene Reihenfolge.</summary>
    SearchPaths: TArray<string>;
    /// <summary>Unit-Namespaces (DCC_Namespace), z. B. System, Vcl, Winapi.</summary>
    Namespaces: TArray<string>;
    Units: TArray<TProjectUnit>;
    /// <summary>Alle ausgewerteten Eigenschaften als Name=Wert, für Diagnose und spätere Auswertungen.</summary>
    Properties: TArray<TPair<string, string>>;
  end;

  /// <summary>Bibliothekspfade einer Delphi-Installation je Plattform.</summary>
  ILibraryPathProvider = interface
    ['{5B9C3E17-82A4-4D6F-9E01-7A2C4B8D3F65}']
    /// <summary>Suchpfade der Bibliothek (z. B. lib\win64\release), absolut.</summary>
    function LibraryPaths(const APlatform: string): TArray<string>;
    /// <summary>Quellpfade (Browsing Path), z. B. source\rtl\sys, absolut.</summary>
    function BrowsingPaths(const APlatform: string): TArray<string>;
    /// <summary>Werte für $(BDS), $(BDSLIB) usw. als Name=Wert.</summary>
    function Variables: TArray<TPair<string, string>>;
  end;

  EProjectError = class(Exception);

implementation

end.
