package hunk.zombband.camera;
import java.lang.reflect.*;
import java.util.IdentityHashMap;
import java.util.Set;
import viewpoint.core.Frame;

/** Transient rendering changes scoped to this client's current musician and stage props. */
public final class PerformanceModels {
    private static volatile Object performer;
    private static volatile long refreshed;
    private static final IdentityHashMap<Object,Long> band=new IdentityHashMap<>();
    private static final long TIMEOUT=1_500_000_000L;
    private static final int SELF_FLAG=64;
    private static final int SOLID_FLAG=128;
    /** Explicit Viewpoint SOLID-flagged ZOMB-BAND instrument and stage prop models. */
    private static final Set<String> SOLID_MODELS=Set.of(
        "ZombBand_DrumKit_Prop",
        "ZombBand_MicrophoneStand",
        "ZombBand_AcousticGuitar",
        "ZombBand_ElectricGuitar",
        "ZombBand_BassGuitar",
        "ZombBand_ViolinBow",
        "Drumstick",
        "Microphone"
    );
    private record Span(Object draws,int first,Object actor) {}
    private static final ThreadLocal<Span> span=new ThreadLocal<>();
    private static Field flags,instances,boneName,modelField,modelNameField,modelScriptField;
    private static Method indices,scriptNameMethod;
    public static void refresh(Object p) { performer=p;refreshed=System.nanoTime(); }
    public static void clear() { performer=null;span.remove();synchronized(band) { band.clear(); } }
    public static void protect(Object p) {
        if(p==null)return;long now=System.nanoTime();
        synchronized(band) { band.entrySet().removeIf(e->now-e.getValue()>TIMEOUT);band.put(p,now); }
    }
    private static boolean protectedActor(Object p) {
        if(owns(p))return true;
        if(!ZombBandCamera.active())return false;
        synchronized(band) { Long at=band.get(p);return at!=null && System.nanoTime()-at<TIMEOUT; }
    }
    public static boolean owns(Object p) { return p!=null && p==performer && System.nanoTime()-refreshed<TIMEOUT; }
    public static void capture(Object[] args) {
        span.remove();
        if(args.length<5 || !protectedActor(args[2]))return;
        // Use the authored instrument pose instead of Viewpoint's local-player
        // procedural foot/attachment adjustment. Keep its head-hiding argument.
        if(owns(args[2]))args[3]=false;
        Frame frame=(Frame)args[0];span.set(new Span(frame.scene.models,frame.scene.models.count(),args[2]));
    }
    public static void afterCapture() {
        Span range=span.get();if(range!=null)apply(range,range.draws,range.first);
    }
    public static void afterOwn(Object draws,int first) {
        Span range=span.get();span.remove();apply(range,draws,first);
    }
    private static void initReflection(Class<?> c) throws Exception {
        if(flags!=null)return;
        flags=field(c,"flags");instances=field(c,"instances");
        indices=c.getDeclaredMethod("indices",int.class);indices.setAccessible(true);
        Class<?> mi=Class.forName("zombie.core.skinnedmodel.model.ModelInstance");
        boneName=mi.getField("parentBoneName");
        modelField=mi.getField("model");
        modelScriptField=mi.getField("modelScript");
        modelNameField=Class.forName("zombie.core.skinnedmodel.model.Model").getField("name");
        scriptNameMethod=Class.forName("zombie.scripting.objects.ModelScript").getMethod("getName");
    }
    private static boolean isRegisteredProp(Object modelInstance) {
        try {
            Object script=modelScriptField.get(modelInstance);
            if(script!=null) {
                String sn=(String)scriptNameMethod.invoke(script);
                if(sn!=null && (SOLID_MODELS.contains(sn) || sn.startsWith("ZombBand_")))return true;
            }
            Object mdl=modelField.get(modelInstance);
            if(mdl!=null) {
                String mn=(String)modelNameField.get(mdl);
                if(mn!=null && (SOLID_MODELS.contains(mn) || mn.contains("ZombBand/") || mn.contains("DrumKit") || mn.contains("MicrophoneStand")))return true;
            }
        } catch(Throwable ignored) {}
        return false;
    }
    private static void apply(Span range,Object draws,int first) {
        if(range==null || range.draws!=draws || range.first!=first || !protectedActor(range.actor))return;
        try {
            Class<?> c=draws.getClass();
            initReflection(c);
            int[] values=(int[])flags.get(draws);Object[] models=(Object[])instances.get(draws);
            int count=(Integer)c.getMethod("count").invoke(draws);
            for(int i=first;i<count;i++) {
                if(models[i]==null)continue;
                String bone=(String)boneName.get(models[i]);
                if(bone!=null && bone.contains("Head"))continue;
                boolean held=bone!=null && (bone.contains("Prop1") || bone.contains("Prop2") || bone.contains("Hand"));
                if(!held && !isRegisteredProp(models[i]))continue;
                // Removing SELF alone selects the world/wall clear cone (kind 0).
                // SOLID (128) selects shader clear kind 2: bypass only camera clearing,
                // retaining ordinary depth/texture alpha and world occlusion.
                values[i]=(values[i] & ~SELF_FLAG) | SOLID_FLAG;indices.invoke(draws,i);
            }
        } catch(Throwable e) { System.out.println("[Zomb-Band MODELS] "+e.getClass().getSimpleName()+": "+e.getMessage());clear(); }
    }
    /** Marks world-placed ZOMB-BAND props (DrumKit, MicrophoneStand, guitars) SOLID during cinematic shots. */
    public static void applyStageProps(Frame frame) {
        if(frame==null || frame.scene==null || frame.scene.models==null || !ZombBandCamera.active())return;
        try {
            Object draws=frame.scene.models;
            Class<?> c=draws.getClass();
            initReflection(c);
            int[] values=(int[])flags.get(draws);Object[] models=(Object[])instances.get(draws);
            int count=frame.scene.models.count();
            for(int i=0;i<count;i++) {
                if(models[i]==null || (values[i] & SOLID_FLAG)!=0)continue;
                if(isRegisteredProp(models[i])) {
                    values[i]=(values[i] & ~SELF_FLAG) | SOLID_FLAG;indices.invoke(draws,i);
                }
            }
        } catch(Throwable ignored) {}
    }
    private static Field field(Class<?> c,String name) throws Exception { Field f=c.getDeclaredField(name);f.setAccessible(true);return f; }
    private PerformanceModels() {}
}
