package hunk.zombband.camera;

import java.lang.reflect.Field;
import me.zed_0xff.zombie_buddy.Exposer;
import viewpoint.core.Frame;
import viewpoint.core.View;
import viewpoint.input.Camera;
import viewpoint.input.FreeCam;
import viewpoint.input.Look;

/** Client-only transient camera lease. No saved options, actors or world state are changed. */
@Exposer.LuaClass
public final class ZombBandCamera {
    private static final long TIMEOUT=1_500_000_000L;
    private static volatile Transition motion;
    private static Snapshot saved;
    private static Field frameField,eyeField,dirField,upField;
    private static volatile long draws;
    private static Object controls;
    private static boolean blocked,context;
    private static volatile String error="";
    private record Pose(double x,double y,double z,float yaw,float pitch,long at) {}
    private record Transition(Pose from,Pose to,long duration) {}
    private record Snapshot(boolean enabled,boolean third,int shoulder,float yaw,float pitch,float zoom,boolean capture) {}

    public static String version() { return "0.8.1"; }
    public static String diagnostics() { return "poses="+(motion==null?"none":"active")+", rendered="+draws+", "+error; }
    public static String error() { return error; }
    public static long frames() { return draws; }
    public static void setPerformer(Object player) { PerformanceModels.refresh(player); }
    public static void clearPerformer() { PerformanceModels.clear(); }
    public static void protectPerformer(Object player) { PerformanceModels.protect(player); }
    public static boolean available() {
        try {
            Class<?> drawer=Class.forName("viewpoint.SceneDrawer");
            drawer.getDeclaredMethod("lookAlong");
            if(frameField==null) {
                frameField=field(drawer,"frame");eyeField=field(drawer,"eye");
                dirField=field(drawer,"dir");upField=field(drawer,"up");
            }
            return true;
        } catch(Throwable e) { error="Unsupported Viewpoint camera API: "+e.getClass().getSimpleName();return false; }
    }
    private static Field field(Class<?> c,String name) throws Exception {
        Field f=c.getDeclaredField(name);f.setAccessible(true);return f;
    }
    public static synchronized boolean begin() {
        if(saved!=null)return true;
        if(!available())return false;
        saved=new Snapshot(View.enabled,View.thirdPerson,View.shoulder,Look.yaw,Look.pitch,Look.zoom,Look.wantCapture);
        draws=0;error="";
        View.enabled=true;View.thirdPerson=true;Look.wantCapture=false;
        return true;
    }
    public static synchronized void lockControls(Object player) throws Exception {
        if(controls!=null)return;
        Class<?> c=player.getClass();
        boolean oldBlock=(Boolean)c.getMethod("isBlockMovement").invoke(player);
        boolean oldContext=(Boolean)c.getMethod("isIgnoreContextKey").invoke(player);
        controls=player;blocked=oldBlock;context=oldContext;
        c.getMethod("setBlockMovement",boolean.class).invoke(player,true);
        c.getMethod("setIgnoreContextKey",boolean.class).invoke(player,true);
    }
    /** Coordinates use Zomboid tiles; vertical height uses floor units (one floor = sqrt(6) world units). */
    public static synchronized boolean setPose(double x,double y,double z,double tx,double ty,double tz,boolean cut) {
        if(!Double.isFinite(x+y+z+tx+ty+tz))return false;
        if(saved==null && !begin())return false;
        double dx=tx-x,dy=ty-y,up=(tz-z)*2.4494895935058594;
        double horizontal=Math.hypot(dx,dy);
        if(horizontal<0.01)return false;
        long now=System.nanoTime();Transition old=motion;
        boolean snap=cut || old==null || now-old.to.at>TIMEOUT;
        long duration=old==null?33_000_000L:Math.max(16_000_000L,Math.min(100_000_000L,now-old.to.at));
        // Start from the current interpolated lens, never the old target. An
        // early/late simulation update cannot rewind the rendered trajectory.
        Pose from=snap?null:sample(old,now);
        motion=new Transition(from,new Pose(x,y,z,(float)Math.atan2(dy,dx),(float)Math.atan2(up,horizontal),now),duration);
        View.enabled=true;View.thirdPerson=true;Look.wantCapture=false;
        return true;
    }
    public static synchronized void stop() {
        motion=null;
        Object player=controls;controls=null;
        if(player!=null)try {
            player.getClass().getMethod("setBlockMovement",boolean.class).invoke(player,blocked);
            player.getClass().getMethod("setIgnoreContextKey",boolean.class).invoke(player,context);
        } catch(Throwable e) { System.out.println("[Zomb-Band CAMERA] control restore failed: "+e); }
        Snapshot s=saved;saved=null;
        if(s!=null) {
            View.enabled=s.enabled;View.thirdPerson=s.third;View.shoulder=s.shoulder;
            Look.yaw=s.yaw;Look.pitch=s.pitch;Look.zoom=s.zoom;Look.wantCapture=s.capture;
        }
    }
    public static boolean active() {
        Transition current=motion;
        if(current==null)return false;
        Pose p=current.to;
        if(System.nanoTime()-p.at>TIMEOUT) { stop();return false; }
        return true;
    }
    /** Called just before the final view matrix is composed, after other camera controllers. */
    public static void draw(Object drawer) {
        if(!active())return;
        Transition current=motion;if(current==null)return;
        Pose p=sample(current,System.nanoTime());
        try {
            Frame frame=(Frame)frameField.get(drawer);
            PerformanceModels.applyStageProps(frame);
            float[] eye=(float[])eyeField.get(drawer),dir=(float[])dirField.get(drawer),up=(float[])upField.get(drawer);
            Camera.at(frame,new FreeCam.Place(p.x,p.y,p.z,p.yaw,p.pitch),eye,dir);
            up[0]=0;up[1]=1;up[2]=0;
            draws++;
            if(draws==1)System.out.println("[Zomb-Band CAMERA] Native render hook is drawing the performance lens");
        } catch(Throwable e) {
            error="Camera hook failed: "+e.getClass().getSimpleName();
            System.out.println("[Zomb-Band CAMERA] "+error);stop();
        }
    }
    private static Pose sample(Transition path,long now) {
        Pose p=path.to,old=path.from;
        if(old==null)return p;
        double alpha=Math.max(0,Math.min(1,(double)(now-p.at)/path.duration));
        double dyaw=Math.atan2(Math.sin(p.yaw-old.yaw),Math.cos(p.yaw-old.yaw));
        return new Pose(old.x+(p.x-old.x)*alpha,old.y+(p.y-old.y)*alpha,old.z+(p.z-old.z)*alpha,
            (float)(old.yaw+dyaw*alpha),(float)(old.pitch+(p.pitch-old.pitch)*alpha),now);
    }
    private ZombBandCamera() {}
}
