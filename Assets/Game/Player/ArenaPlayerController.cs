using UnityEngine;
using UnityEngine.InputSystem;

// Handles side-view player movement, jumping, grounding, and blast-distance queries.
[RequireComponent(typeof(CharacterController))]
[AddComponentMenu("Arena/Player Controller")]
public sealed class ArenaPlayerController : MonoBehaviour
{
    [Header("Movement")]
    [SerializeField, Min(0f), InspectorName("Move speed (units/s)")]
    private float moveSpeed = 7f;

    [Header("Jump")]
    [SerializeField, Min(0f), InspectorName("Jump height (units)")]
    private float jumpHeight = 2.5f;

    [Tooltip("Player acceleration along Y. Negative values pull downward; separate from bomb acceleration.")]
    [SerializeField, InspectorName("Gravity (units/s²)")]
    private float gravity = -25f;

    [Header("Jump assistance")]
    [Tooltip("How long a jump remains allowed after walking off an edge.")]
    [SerializeField, Range(0f, 0.2f), InspectorName("Coyote time (seconds)")]
    private float coyoteTime = 0.1f;

    [Tooltip("How long a jump pressed before landing is remembered.")]
    [SerializeField, Range(0f, 0.2f), InspectorName("Jump buffer (seconds)")]
    private float jumpBufferTime = 0.1f;

    private CharacterController controller;
    private float verticalSpeed;
    private float coyoteRemaining;
    private float jumpBufferRemaining;
    private bool wasGrounded;
    private Animator animator;

    // Used to remember the player's original scale.
    private Vector3 originalScale;

    private void Awake()
    {
        controller = GetComponent<CharacterController>();
        animator = GetComponentInChildren<Animator>();

        // Save the player's starting scale.
        originalScale = transform.localScale;
    }

    private void Update()
    {
        float input = ReadMovement();

        animator.SetBool("Running", Mathf.Abs(input) > 0.01f);

        // Flip the player depending on movement direction.
        UpdateFacing(input);

        bool grounded = controller.isGrounded;

        if (grounded && !wasGrounded)
            coyoteRemaining = coyoteTime;
        else if (grounded && verticalSpeed <= 0f)
            coyoteRemaining = coyoteTime;
        else
            coyoteRemaining -= Time.deltaTime;

        if (JumpPressed())
            jumpBufferRemaining = jumpBufferTime + Time.deltaTime;
        else
            jumpBufferRemaining -= Time.deltaTime;

        if (grounded && verticalSpeed < 0f)
            verticalSpeed = -2f;

        if (jumpBufferRemaining > 0f && coyoteRemaining >= 0f)
        {
            verticalSpeed = Mathf.Sqrt(-2f * gravity * jumpHeight);
            jumpBufferRemaining = 0f;
            coyoteRemaining = -1f;
        }

        verticalSpeed += gravity * Time.deltaTime;

        Vector3 velocity = new Vector3(
            input * moveSpeed,
            verticalSpeed,
            0f
        );

        controller.Move(velocity * Time.deltaTime);

        if ((controller.collisionFlags & CollisionFlags.Above) != 0
            && verticalSpeed > 0f)
        {
            verticalSpeed = 0f;
        }

        wasGrounded = grounded;
    }

    private void UpdateFacing(float input)
    {
        Vector3 scale = originalScale;

        // Moving left
        if (input < 0f)
        {
            scale.x = -Mathf.Abs(originalScale.x);
        }

        // Moving right
        else if (input > 0f)
        {
            scale.x = Mathf.Abs(originalScale.x);
        }

        // If input is 0, don't change the direction.
        else
        {
            return;
        }

        transform.localScale = scale;
    }

    private static float ReadMovement()
    {
        float input = 0f;

        Keyboard keyboard = Keyboard.current;

        if (keyboard != null)
        {
            if (keyboard.aKey.isPressed ||
                keyboard.leftArrowKey.isPressed)
            {
                input -= 1f;
            }

            if (keyboard.dKey.isPressed ||
                keyboard.rightArrowKey.isPressed)
            {
                input += 1f;
            }
        }

        if (Gamepad.current != null)
        {
            float stick = Gamepad.current.leftStick.ReadValue().x;

            if (Mathf.Abs(stick) > Mathf.Abs(input))
                input = stick;
        }

        return Mathf.Clamp(input, -1f, 1f);
    }

    private static bool JumpPressed()
    {
        Keyboard keyboard = Keyboard.current;

        return (keyboard != null &&
                (keyboard.spaceKey.wasPressedThisFrame
                || keyboard.wKey.wasPressedThisFrame
                || keyboard.upArrowKey.wasPressedThisFrame))
                || (Gamepad.current != null &&
                    Gamepad.current.buttonSouth.wasPressedThisFrame);
    }

    private void OnDisable()
    {
        verticalSpeed = 0f;
        coyoteRemaining = -1f;
        jumpBufferRemaining = 0f;
        wasGrounded = false;
    }

    private void OnControllerColliderHit(ControllerColliderHit hit)
    {
        Rigidbody body = hit.collider.attachedRigidbody;
        if (body == null || hit.collider.GetComponentInParent<GroundRubble>() == null || body.isKinematic) return;
        Vector3 push = new Vector3(hit.moveDirection.x, 0.15f, 0f);
        body.AddForce(push * Mathf.Max(1f, moveSpeed), ForceMode.VelocityChange);
    }

    private void OnValidate()
    {
        gravity = Mathf.Min(gravity, -0.1f);
    }

    // Measure distance to the capsule side in XY, accounting for the capsule end caps.
    public float DistanceToBody(Vector2 point)
    {
        CharacterController body =
            controller != null
            ? controller
            : GetComponent<CharacterController>();

        Vector3 center = transform.TransformPoint(body.center);

        float radius =
            body.radius *
            Mathf.Max(transform.lossyScale.x, transform.lossyScale.z);

        float halfSegment =
            Mathf.Max(
                0f,
                body.height * transform.lossyScale.y * 0.5f - radius
            );

        Vector2 closest = new Vector2(
            center.x,
            Mathf.Clamp(
                point.y,
                center.y - halfSegment,
                center.y + halfSegment
            )
        );

        return Mathf.Max(
            0f,
            Vector2.Distance(point, closest) - radius
        );
    }
}