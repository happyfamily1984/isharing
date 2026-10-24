package com.happyfamily.familylocator

import android.location.Location
import com.google.android.gms.tasks.Tasks
import com.google.firebase.FirebaseApp
import com.google.firebase.auth.FirebaseAuth
import org.json.JSONArray
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import java.util.concurrent.TimeUnit

/**
 * 백그라운드 서비스용 Firestore 쓰기 (REST API).
 *
 * 네이티브 Firestore SDK 를 서비스에서 먼저 쓰면, 나중에 앱(Flutter)이 Firestore 설정을
 * 바꾸려 할 때 "이미 시작됨" 오류가 날 수 있어 서비스는 REST 로만 쓴다.
 * 로그인 정보(FirebaseAuth)는 앱과 공유하고, 보안 규칙도 앱에서 쓸 때와 똑같이 적용된다.
 * 메인 스레드가 아닌 곳에서 호출해야 한다.
 */
object FirestoreRest {
    private val chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"

    fun upload(
        uid: String,
        location: Location,
        battery: Int?,
        charging: Boolean,
        addHistory: Boolean,
        liveOnly: Boolean = false,
    ) {
        val user = FirebaseAuth.getInstance().currentUser ?: return
        val token = Tasks.await(user.getIdToken(false), 30, TimeUnit.SECONDS).token ?: return
        val projectId = FirebaseApp.getInstance().options.projectId ?: return
        val root = "projects/$projectId/databases/(default)/documents"
        val userDoc = "$root/users/$uid"

        val fields = JSONObject()
            .put(
                "lastLocation", JSONObject().put(
                    "mapValue", JSONObject().put(
                        "fields", JSONObject()
                            .put("lat", double(location.latitude))
                            .put("lng", double(location.longitude))
                            .put("accuracy", double(location.accuracy.toDouble()))
                    )
                )
            )
            .put("charging", JSONObject().put("booleanValue", charging))
            // true 면 지도 표시용 위치라 서버가 알림 계산을 건너뛴다
            .put("liveOnly", JSONObject().put("booleanValue", liveOnly))
        val mask = JSONArray().put("lastLocation").put("charging").put("liveOnly")
        if (battery != null) {
            fields.put("battery", JSONObject().put("integerValue", battery.toString()))
            mask.put("battery")
        }
        val writes = JSONArray().put(
            JSONObject()
                .put("update", JSONObject().put("name", userDoc).put("fields", fields))
                .put("updateMask", JSONObject().put("fieldPaths", mask))
                .put(
                    "updateTransforms", JSONArray().put(
                        JSONObject().put("fieldPath", "updatedAt").put("setToServerValue", "REQUEST_TIME")
                    )
                )
        )
        if (addHistory) {
            writes.put(
                JSONObject()
                    .put(
                        "update", JSONObject()
                            .put("name", "$userDoc/locations/${randomId()}")
                            .put(
                                "fields", JSONObject()
                                    .put("lat", double(location.latitude))
                                    .put("lng", double(location.longitude))
                                    .put("accuracy", double(location.accuracy.toDouble()))
                                    .put("ts", JSONObject().put("timestampValue", timestamp(location.time)))
                            )
                    )
                    .put("currentDocument", JSONObject().put("exists", false))
            )
        }

        val conn = URL("https://firestore.googleapis.com/v1/$root:commit").openConnection() as HttpURLConnection
        try {
            conn.requestMethod = "POST"
            conn.connectTimeout = 20_000
            conn.readTimeout = 20_000
            conn.doOutput = true
            conn.setRequestProperty("Authorization", "Bearer $token")
            conn.setRequestProperty("Content-Type", "application/json; charset=utf-8")
            conn.outputStream.use { it.write(JSONObject().put("writes", writes).toString().toByteArray()) }
            val code = conn.responseCode
            if (code !in 200..299) {
                val body = conn.errorStream?.bufferedReader()?.use { it.readText() }
                throw IllegalStateException("Firestore commit failed: $code $body")
            }
        } finally {
            conn.disconnect()
        }
    }

    private fun double(v: Double) = JSONObject().put("doubleValue", v)

    private fun timestamp(ms: Long): String =
        SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US)
            .apply { timeZone = TimeZone.getTimeZone("UTC") }
            .format(Date(ms))

    private fun randomId(): String = (1..20).map { chars.random() }.joinToString("")
}
