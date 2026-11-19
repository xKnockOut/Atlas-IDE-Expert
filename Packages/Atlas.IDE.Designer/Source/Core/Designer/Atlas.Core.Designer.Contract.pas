unit Atlas.Core.Designer.Contract;

// Formular-Designer als schmaler Vertrag des Moduls Designer, ohne VCL und
// Open Tools API: genau das, was die Werkzeuge vom Designer der IDE
// brauchen (Formular, Ändern melden, Komponenten löschen und anlegen,
// Ereignis-Handler). In der IDE steht dahinter IDesigner samt
// Formular-Editor (Atlas.IDE.Designer.Adapters.Surface), in den Tests eine
// Fälschung mit echten Komponenten auf einem unsichtbaren Formular. So lassen
// sich Abläufe prüfen, die sonst nur in der IDE prüfbar sind: Komponente wird
// während eines Schritts gelöscht, Formular wird geschlossen, mehrere
// Werkzeuge ändern nacheinander. Nur im Hauptthread.

interface

uses
  System.Classes,
  System.TypInfo;

type
  IAtlasDesignSurface = interface
    ['{2D71ECE3-271E-41F9-B0AD-1E7DEFA284CF}']
    /// <summary>Formular im Designer (Wurzelkomponente); nil, wenn der Designer schon leer ist.</summary>
    function Root: TComponent;
    /// <summary>Meldet dem Designer eine Änderung (Objektinspektor, Speichern-Marke).</summary>
    procedure Modified;
    /// <summary>Löscht die Komponente zum Schlüssel AKey („Button1“, in Frames „Frame1.Button1“) wie der
    /// Designer, also samt Feld in der Klasse; False, wenn das nicht geht.</summary>
    function DeleteComponent(const AKey: string): Boolean;
    /// <summary>Legt eine Komponente der Klasse AClass in AParent an, mit Namen nach den Regeln des Designers;
    /// nil, wenn das nicht geht.</summary>
    function CreateComponent(AClass: TComponentClass; AParent: TComponent): TComponent;
    /// <summary>Steht die Methode AName im Code des Formulars?</summary>
    function MethodExists(const AName: string): Boolean;
    /// <summary>Handler AName für ein Ereignis vom Typ ATypeData.</summary>
    function CreateMethod(const AName: string; ATypeData: PTypeData): TMethod;
    /// <summary>Name des Handlers AMethod; '' = unbekannt.</summary>
    function MethodName(const AMethod: TMethod): string;
  end;

implementation

end.
